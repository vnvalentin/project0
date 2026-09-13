package bridge

import (
	"fmt"
	"log"
	"net"
	"net/netip"
	"strconv"
	"strings"
	"sync"

	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun/netstack"
)

// Bridge owns one netstack WireGuard device plus the loopback<->netstack UDP
// relay that lets a local ENet client tunnel to the game host transparently.
type Bridge struct {
	mu sync.Mutex

	dev        *device.Device
	loopback   *net.UDPConn
	netstackUC net.Conn

	loopbackPeer   *net.UDPAddr
	loopbackPeerMu sync.RWMutex

	stopCh chan struct{}
	wg     sync.WaitGroup
}

// Start validates cfg, builds the netstack WireGuard device, brings it up,
// opens the real loopback socket, and begins bridging datagrams. It returns
// the chosen ephemeral loopback port on success.
func Start(cfg Config) (*Bridge, int, error) {
	privKeyB64, err := readPrivateKeyBase64(cfg.ClientPrivateKeyPath)
	if err != nil {
		return nil, -1, err
	}
	privKeyHex, err := base64KeyToHex(privKeyB64)
	if err != nil {
		return nil, -1, fmt.Errorf("client private key: %w", err)
	}
	pubKeyHex, err := base64KeyToHex(cfg.ServerPublicKey)
	if err != nil {
		return nil, -1, fmt.Errorf("server public key: %w", err)
	}

	clientPrefix, err := netip.ParsePrefix(cfg.ClientAddress)
	if err != nil {
		return nil, -1, fmt.Errorf("invalid client_address %q: %w", cfg.ClientAddress, err)
	}

	tunDev, tnet, err := netstack.CreateNetTUN(
		[]netip.Addr{clientPrefix.Addr()},
		[]netip.Addr{},
		cfg.MTU,
	)
	if err != nil {
		return nil, -1, fmt.Errorf("creating netstack tun: %w", err)
	}

	dev := device.NewDevice(tunDev, conn.NewDefaultBind(), device.NewLogger(device.LogLevelError, "wgnetstack: "))

	ipc := strings.Builder{}
	fmt.Fprintf(&ipc, "private_key=%s\n", privKeyHex)
	fmt.Fprintf(&ipc, "public_key=%s\n", pubKeyHex)
	fmt.Fprintf(&ipc, "endpoint=%s\n", cfg.ServerEndpoint)
	fmt.Fprintf(&ipc, "persistent_keepalive_interval=%d\n", cfg.PersistentKeepaliveInterval)
	fmt.Fprintf(&ipc, "allowed_ip=0.0.0.0/0\n")

	if err := dev.IpcSet(ipc.String()); err != nil {
		dev.Close()
		return nil, -1, fmt.Errorf("configuring wireguard device: %w", err)
	}

	if err := dev.Up(); err != nil {
		dev.Close()
		return nil, -1, fmt.Errorf("bringing wireguard device up: %w", err)
	}

	gameHostAddr, err := resolveAddrPort(cfg.GameHost)
	if err != nil {
		dev.Close()
		return nil, -1, fmt.Errorf("invalid game_host %q: %w", cfg.GameHost, err)
	}

	netstackConn, err := tnet.DialUDPAddrPort(netip.AddrPort{}, gameHostAddr)
	if err != nil {
		dev.Close()
		return nil, -1, fmt.Errorf("dialing game host through netstack: %w", err)
	}

	loopbackAddr, err := net.ResolveUDPAddr("udp", "127.0.0.1:0")
	if err != nil {
		netstackConn.Close()
		dev.Close()
		return nil, -1, fmt.Errorf("resolving loopback address: %w", err)
	}
	loopbackConn, err := net.ListenUDP("udp", loopbackAddr)
	if err != nil {
		netstackConn.Close()
		dev.Close()
		return nil, -1, fmt.Errorf("opening loopback socket: %w", err)
	}

	port := loopbackConn.LocalAddr().(*net.UDPAddr).Port

	b := &Bridge{
		dev:        dev,
		loopback:   loopbackConn,
		netstackUC: netstackConn,
		stopCh:     make(chan struct{}),
	}

	b.wg.Add(2)
	go b.pumpLoopbackToNetstack()
	go b.pumpNetstackToLoopback()

	log.Printf("wgnetstack: bridge started, loopback port %d -> %s via %s", port, cfg.GameHost, cfg.ServerEndpoint)
	return b, port, nil
}

// Stop tears down both relay goroutines, the netstack UDP dial, the loopback
// socket, and the WireGuard device.
func (b *Bridge) Stop() {
	b.mu.Lock()
	defer b.mu.Unlock()

	select {
	case <-b.stopCh:
		return // already stopped
	default:
		close(b.stopCh)
	}

	b.loopback.Close()
	b.netstackUC.Close()
	b.wg.Wait()
	b.dev.Close()
	log.Printf("wgnetstack: bridge stopped")
}

func (b *Bridge) pumpLoopbackToNetstack() {
	defer b.wg.Done()
	buf := make([]byte, 65535)
	for {
		n, peer, err := b.loopback.ReadFromUDP(buf)
		if err != nil {
			select {
			case <-b.stopCh:
				return
			default:
				log.Printf("wgnetstack: loopback read error: %v", err)
				return
			}
		}
		b.rememberLoopbackPeer(peer)
		if _, err := b.netstackUC.Write(buf[:n]); err != nil {
			select {
			case <-b.stopCh:
				return
			default:
				log.Printf("wgnetstack: netstack write error: %v", err)
				return
			}
		}
	}
}

func (b *Bridge) pumpNetstackToLoopback() {
	defer b.wg.Done()
	buf := make([]byte, 65535)
	for {
		n, err := b.netstackUC.Read(buf)
		if err != nil {
			select {
			case <-b.stopCh:
				return
			default:
				log.Printf("wgnetstack: netstack read error: %v", err)
				return
			}
		}
		peer := b.currentLoopbackPeer()
		if peer == nil {
			continue // no local ENet client has sent a datagram yet
		}
		if _, err := b.loopback.WriteToUDP(buf[:n], peer); err != nil {
			select {
			case <-b.stopCh:
				return
			default:
				log.Printf("wgnetstack: loopback write error: %v", err)
				return
			}
		}
	}
}

func (b *Bridge) rememberLoopbackPeer(addr *net.UDPAddr) {
	b.loopbackPeerMu.Lock()
	defer b.loopbackPeerMu.Unlock()
	b.loopbackPeer = addr
}

func (b *Bridge) currentLoopbackPeer() *net.UDPAddr {
	b.loopbackPeerMu.RLock()
	defer b.loopbackPeerMu.RUnlock()
	return b.loopbackPeer
}

func resolveAddrPort(hostPort string) (netip.AddrPort, error) {
	host, portStr, err := net.SplitHostPort(hostPort)
	if err != nil {
		return netip.AddrPort{}, err
	}
	port, err := strconv.ParseUint(portStr, 10, 16)
	if err != nil {
		return netip.AddrPort{}, fmt.Errorf("invalid port %q: %w", portStr, err)
	}
	addr, err := netip.ParseAddr(host)
	if err != nil {
		ips, lookupErr := net.LookupIP(host)
		if lookupErr != nil || len(ips) == 0 {
			return netip.AddrPort{}, fmt.Errorf("resolving host %q: %w", host, err)
		}
		addr, err = netip.ParseAddr(ips[0].String())
		if err != nil {
			return netip.AddrPort{}, err
		}
	}
	return netip.AddrPortFrom(addr, uint16(port)), nil
}
