function Initialize-TransportJob {
    if ('WindowsValidationJob' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
public sealed class WindowsValidationJob : IDisposable {
    [StructLayout(LayoutKind.Sequential)] struct BasicLimits {
        public long ProcessTime, JobTime;
        public uint Flags;
        public UIntPtr MinimumWorkingSet, MaximumWorkingSet;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint Priority, Scheduling;
    }
    [StructLayout(LayoutKind.Sequential)] struct IoCounters {
        public ulong ReadOperations, WriteOperations, OtherOperations, ReadBytes, WriteBytes, OtherBytes;
    }
    [StructLayout(LayoutKind.Sequential)] struct ExtendedLimits {
        public BasicLimits Basic;
        public IoCounters Io;
        public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
    }
    [StructLayout(LayoutKind.Sequential)] struct Accounting {
        public long UserTime, KernelTime, PeriodUserTime, PeriodKernelTime;
        public uint PageFaults, TotalProcesses, ActiveProcesses, TerminatedProcesses;
    }
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetInformationJobObject(IntPtr job, int info, ref ExtendedLimits limits, uint size);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool TerminateJobObject(IntPtr job, uint code);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool QueryInformationJobObject(IntPtr job, int info, out Accounting accounting, uint size, IntPtr returned);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    IntPtr handle;
    static void Require(bool success) { if (!success) throw new Win32Exception(Marshal.GetLastWin32Error()); }
    public WindowsValidationJob() {
        handle = CreateJobObject(IntPtr.Zero, null);
        if (handle == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        try {
            ExtendedLimits limits = new ExtendedLimits();
            limits.Basic.Flags = 0x2000;
            Require(SetInformationJobObject(handle, 9, ref limits, (uint)Marshal.SizeOf(typeof(ExtendedLimits))));
        } catch { CloseHandle(handle); handle = IntPtr.Zero; throw; }
    }
    public void Attach(Process process) { Require(AssignProcessToJobObject(handle, process.Handle)); }
    public void Stop() {
        Require(TerminateJobObject(handle, 1));
        Stopwatch clock = Stopwatch.StartNew();
        using (ManualResetEvent pause = new ManualResetEvent(false)) {
            do {
                Accounting accounting;
                Require(QueryInformationJobObject(handle, 1, out accounting, (uint)Marshal.SizeOf(typeof(Accounting)), IntPtr.Zero));
                if (accounting.ActiveProcesses == 0) return;
                pause.WaitOne(10);
            } while (clock.ElapsedMilliseconds < 5000);
        }
        throw new TimeoutException("Transport job descendants did not stop");
    }
    public void Dispose() {
        if (handle != IntPtr.Zero) { CloseHandle(handle); handle = IntPtr.Zero; }
    }
}
'@
}

function Invoke-Transport([string]$Executable, [string[]]$Arguments, [string]$Operation, [hashtable]$Parameters) {
    $bootstrap = '$ErrorActionPreference = "Stop"; $request = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([Console]::In.ReadLine())) | ConvertFrom-Json; if ($request.parameters) { $parameters = @{}; foreach ($property in $request.parameters.PSObject.Properties) { $parameters[$property.Name] = $property.Value }; & $request.executable @parameters } else { $arguments = @($request.arguments); & $request.executable @arguments }; exit $LASTEXITCODE'
    $workerPath = Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $start = [Diagnostics.ProcessStartInfo]::new($workerPath)
    [void]$start.Environment.Remove('PSModulePath')
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('-NoProfile', '-NonInteractive', '-EncodedCommand', [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($bootstrap)))) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $job = $null
    $started = $false
    $output = $null
    $errors = $null
    $failure = $null
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $record = [ordered]@{ operation = $Operation; worker_path = $workerPath; worker_sha256 = $null; worker_pid = $null; job_assigned = $false; job_empty = $false; timeout_seconds = $TransportTimeoutSeconds; exit_code = $null; timed_out = $false; stopped = $false; failure = $null }
    try {
        $record.worker_sha256 = (Get-FileHash -LiteralPath $workerPath).Hash
        Initialize-TransportJob
        $job = [WindowsValidationJob]::new()
        $started = $process.Start()
        $record.worker_pid = $process.Id
        $output = $process.StandardOutput.ReadToEndAsync()
        $errors = $process.StandardError.ReadToEndAsync()
        $job.Attach($process)
        $record.job_assigned = $true
        $request = @{ executable = $Executable; arguments = $Arguments; parameters = $Parameters } | ConvertTo-Json -Compress
        $process.StandardInput.WriteLine([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($request)))
        $process.StandardInput.Close()
        if (-not $process.WaitForExit($TransportTimeoutSeconds * 1000)) {
            $record.timed_out = $true
            throw "$Operation timed out after $TransportTimeoutSeconds seconds"
        }
        $record.exit_code = $process.ExitCode
        if (-not $output.Wait(1000) -or -not $errors.Wait(1000)) { throw "$Operation output capture timed out" }
        if ($process.ExitCode -ne 0) { throw "$Operation failed with exit code $($process.ExitCode)" }
    }
    catch { $failure = $_.Exception.Message }
    finally {
        try {
            if ($job) { $job.Stop(); $record.job_empty = $true }
            if ($started -and -not $process.HasExited) {
                $process.Kill($true)
                if (-not $process.WaitForExit(5000)) { throw "$Operation owned process did not stop" }
            }
            $record.stopped = -not $started -or $process.HasExited
            if ($started) { $record.exit_code = $process.ExitCode }
        }
        catch { $failure += "; $($_.Exception.Message)" }
        finally {
            if ($job) { $job.Dispose() }
            $process.Dispose()
            $record.failure = $failure
            $record.elapsed_seconds = $clock.Elapsed.TotalSeconds
            $result.transport += $record
        }
    }
    if ($failure) { throw $failure }
    return $output.GetAwaiter().GetResult()
}