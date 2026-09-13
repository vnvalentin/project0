.PHONY: linux windows probe cgoarchive clean

linux:
	CGO_ENABLED=1 go build -buildmode=c-shared -o build/libwgnetstack.so ./cmd/cshared

windows:
	CC=x86_64-w64-mingw32-gcc GOOS=windows GOARCH=amd64 CGO_ENABLED=1 go build -buildmode=c-shared -o build/wgnetstack.dll ./cmd/cshared

probe:
	go build -o build/probe ./cmd/probe

# Slice 034: static c-archive (.a + .h) of the same bridge C ABI as `linux`,
# for the GDExtension (native/wgnetstack/gdext/) to link directly instead of
# dlopen-ing a sibling shared library at runtime.
cgoarchive:
	CGO_ENABLED=1 go build -buildmode=c-archive -o build/libwgnetstack.a ./cmd/cgoarchive

clean:
	rm -f build/libwgnetstack.so build/libwgnetstack.h build/wgnetstack.dll build/wgnetstack.h build/probe build/libwgnetstack.a build/libwgnetstack_gdext.h
