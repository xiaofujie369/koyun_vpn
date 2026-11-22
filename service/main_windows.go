//go:build windows

// Koyun 后台服务（Windows）：安装时以管理员身份注册，以 SYSTEM 运行。
// App 开 TUN 时通过它启动内核，不再需要每次弹管理员确认。
//
//	koyun-service.exe sid                     打印当前用户 SID（安装包以原始用户身份调用）
//	koyun-service.exe install --owner <SID>   注册并启动服务（需要管理员）
//	koyun-service.exe uninstall               停止并删除服务（需要管理员）
//	koyun-service.exe run --owner <SID>       由系统服务管理器调用
//	koyun-service.exe debug --owner <SID>     前台运行（测试用）
package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/svc"
	"golang.org/x/sys/windows/svc/mgr"
)

const svcName = "KoyunService"

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: koyun-service sid|install|uninstall|run|debug [--owner SID]")
		os.Exit(2)
	}
	owner := ""
	for i := 2; i+1 < len(os.Args); i++ {
		if os.Args[i] == "--owner" {
			owner = os.Args[i+1]
		}
	}
	var err error
	switch os.Args[1] {
	case "sid":
		var s string
		s, err = currentSID()
		if err == nil {
			fmt.Print(s)
		}
	case "install":
		if err = checkOwner(owner); err == nil {
			err = install(owner)
		}
	case "uninstall":
		err = uninstall()
	case "run":
		if err = checkOwner(owner); err == nil {
			err = svc.Run(svcName, &handler{owner: owner})
		}
	case "debug":
		if err = checkOwner(owner); err == nil {
			stop := make(chan struct{})
			go func() {
				c := make(chan os.Signal, 1)
				signal.Notify(c, os.Interrupt, syscall.SIGTERM)
				<-c
				close(stop)
			}()
			err = serve(owner, stop)
		}
	default:
		err = fmt.Errorf("unknown command %q", os.Args[1])
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "koyun-service:", err)
		os.Exit(1)
	}
}

func checkOwner(owner string) error {
	if owner == "" {
		return errors.New("missing --owner SID")
	}
	if _, err := windows.StringToSid(owner); err != nil {
		return fmt.Errorf("bad owner SID %q: %w", owner, err)
	}
	return nil
}

func currentSID() (string, error) {
	u, err := windows.GetCurrentProcessToken().GetTokenUser()
	if err != nil {
		return "", err
	}
	return u.User.Sid.String(), nil
}

func exeDir() string {
	exe, err := os.Executable()
	if err != nil {
		panic(err)
	}
	return filepath.Dir(exe)
}

// StateDir 在安装目录（Program Files，只有管理员可写）下，普通用户无法抢先创建或放入链接。
// 权限：SYSTEM / 管理员完全控制，安装用户只读（读令牌和日志），其他用户无权访问
func stateDir() string { return filepath.Join(exeDir(), "service-data") }

func secureDir(dir, owner string) error {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	sd, err := windows.SecurityDescriptorFromString(
		"D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;" + owner + ")")
	if err != nil {
		return err
	}
	dacl, _, err := sd.DACL()
	if err != nil {
		return err
	}
	return windows.SetNamedSecurityInfo(dir, windows.SE_FILE_OBJECT,
		windows.DACL_SECURITY_INFORMATION|windows.PROTECTED_DACL_SECURITY_INFORMATION, nil, nil, dacl, nil)
}

// serve 运行接口直到 stop 被关闭
func serve(owner string, stop <-chan struct{}) error {
	dir := stateDir()
	if err := secureDir(dir, owner); err != nil {
		return fmt.Errorf("secure %s: %w", dir, err)
	}
	core := &coreManager{binary: filepath.Join(exeDir(), "sing-box.exe"), dataDir: filepath.Join(dir, "core")}
	// 开机 / 服务重启时先清一次残留网卡（上次关机时内核可能没正常退出）
	go cleanupTunGhosts()
	l, port, err := listenLocal()
	if err != nil {
		return err
	}
	api := &apiServer{core: core, token: newToken(), host: fmt.Sprintf("127.0.0.1:%d", port)}
	state, _ := json.Marshal(stateFile{Port: port, Token: api.token, Version: serviceVersion})
	statePath := filepath.Join(dir, "service.json")
	if err := os.WriteFile(statePath, state, 0o600); err != nil {
		l.Close()
		return err
	}
	srv := &http.Server{Handler: api, ReadHeaderTimeout: 10 * time.Second}
	errc := make(chan error, 1)
	go func() { errc <- srv.Serve(l) }()
	select {
	case <-stop:
	case err = <-errc:
	}
	core.stop()
	_ = srv.Close()
	_ = os.Remove(statePath)
	if errors.Is(err, http.ErrServerClosed) {
		err = nil
	}
	return err
}

type handler struct{ owner string }

func (h *handler) Execute(_ []string, r <-chan svc.ChangeRequest, s chan<- svc.Status) (bool, uint32) {
	s <- svc.Status{State: svc.StartPending}
	stop := make(chan struct{})
	errc := make(chan error, 1)
	go func() { errc <- serve(h.owner, stop) }()
	s <- svc.Status{State: svc.Running, Accepts: svc.AcceptStop | svc.AcceptShutdown}
	for {
		select {
		case c := <-r:
			switch c.Cmd {
			case svc.Interrogate:
				s <- c.CurrentStatus
			case svc.Stop, svc.Shutdown:
				s <- svc.Status{State: svc.StopPending}
				close(stop)
				<-errc
				return false, 0
			}
		case err := <-errc:
			if err != nil {
				return true, 1 // 异常退出：由“失败后重启”策略拉起
			}
			return false, 0
		}
	}
}

func install(owner string) error {
	m, err := mgr.Connect()
	if err != nil {
		return err
	}
	defer m.Disconnect()
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	bin := syscall.EscapeArg(exe) + " run --owner " + syscall.EscapeArg(owner)
	s, err := m.OpenService(svcName)
	if err == nil {
		// 已安装（升级）：先停，再改成新的路径和所有者
		stopAndWait(s)
		cfg, err := s.Config()
		if err == nil {
			cfg.BinaryPathName = bin
			cfg.StartType = mgr.StartAutomatic
			err = s.UpdateConfig(cfg)
		}
		if err != nil {
			s.Close()
			return err
		}
	} else {
		s, err = m.CreateService(svcName, exe, mgr.Config{
			DisplayName: "Koyun Service",
			Description: "Koyun: starts the VPN core for TUN mode without asking for administrator rights each time.",
			StartType:   mgr.StartAutomatic,
		}, "run", "--owner", owner)
		if err != nil {
			return err
		}
	}
	defer s.Close()
	_ = s.SetRecoveryActions([]mgr.RecoveryAction{
		{Type: mgr.ServiceRestart, Delay: 5 * time.Second},
		{Type: mgr.ServiceRestart, Delay: 5 * time.Second},
		{Type: mgr.ServiceRestart, Delay: 30 * time.Second},
	}, 24*60*60)
	if err := s.Start(); err != nil {
		return err
	}
	return waitState(s, svc.Running)
}

func uninstall() error {
	m, err := mgr.Connect()
	if err != nil {
		return err
	}
	defer m.Disconnect()
	s, err := m.OpenService(svcName)
	if err != nil {
		return nil // 没装
	}
	defer s.Close()
	stopAndWait(s)
	return s.Delete()
}

func stopAndWait(s *mgr.Service) {
	if st, err := s.Query(); err == nil && st.State != svc.Stopped {
		_, _ = s.Control(svc.Stop)
		_ = waitState(s, svc.Stopped)
	}
}

func waitState(s *mgr.Service, want svc.State) error {
	for i := 0; i < 150; i++ {
		st, err := s.Query()
		if err != nil {
			return err
		}
		if st.State == want {
			return nil
		}
		time.Sleep(100 * time.Millisecond)
	}
	return fmt.Errorf("service did not reach state %d", want)
}
