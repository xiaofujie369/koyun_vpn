package main

import (
	"bufio"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// coreManager 启动 / 停止内核并收集它的输出。同一时间只运行一个内核。
type coreManager struct {
	binary  string // 只运行安装目录里的 sing-box，路径由服务自己决定，不接受客户端传入
	dataDir string // 配置、缓存都放在这里（只有 SYSTEM 和管理员可写）

	mu       sync.Mutex
	cmd      *exec.Cmd
	done     chan struct{}
	exitCode *int
	logs     []string // 环形缓冲
	logBase  int      // logs[0] 的序号
	lastErr  string
}

const maxLogs = 500

type coreStatus struct {
	Running  bool   `json:"running"`
	Pid      int    `json:"pid,omitempty"`
	ExitCode *int   `json:"exit_code,omitempty"`
	Error    string `json:"error,omitempty"`
}

func (m *coreManager) status() coreStatus {
	m.mu.Lock()
	defer m.mu.Unlock()
	s := coreStatus{ExitCode: m.exitCode, Error: m.lastErr}
	if m.cmd != nil && m.exitCode == nil {
		s.Running = true
		s.Pid = m.cmd.Process.Pid
	}
	return s
}

// logsSince 返回序号 >= since 的日志，以及下一次要用的序号
func (m *coreManager) logsSince(since int) ([]string, int) {
	m.mu.Lock()
	defer m.mu.Unlock()
	next := m.logBase + len(m.logs)
	if since < m.logBase {
		since = m.logBase
	}
	if since >= next {
		return []string{}, next
	}
	return append([]string(nil), m.logs[since-m.logBase:]...), next
}

func (m *coreManager) addLog(line string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.logs = append(m.logs, line)
	if len(m.logs) > maxLogs {
		drop := len(m.logs) - maxLogs
		m.logs = m.logs[drop:]
		m.logBase += drop
	}
	if strings.Contains(line, "FATAL") || strings.Contains(line, "ERROR") {
		m.lastErr = line
	}
}

// start 写入（已收紧的）配置并启动内核；1.2 秒内退出视为启动失败（配置错误、端口占用、网卡创建失败）
func (m *coreManager) start(config []byte) (coreStatus, error) {
	clean, err := sanitizeConfig(config)
	if err != nil {
		return coreStatus{}, err
	}
	m.stop()
	if err := os.MkdirAll(m.dataDir, 0o700); err != nil {
		return coreStatus{}, err
	}
	cfgPath := filepath.Join(m.dataDir, "config.json")
	if err := os.WriteFile(cfgPath, clean, 0o600); err != nil {
		return coreStatus{}, err
	}
	cmd := exec.Command(m.binary, "run", "-c", cfgPath, "-D", m.dataDir)
	cmd.Dir = m.dataDir
	cmd.Env = append(os.Environ(), "ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true")
	hideWindow(cmd)
	out, err := cmd.StdoutPipe()
	if err != nil {
		return coreStatus{}, err
	}
	cmd.Stderr = cmd.Stdout
	m.mu.Lock()
	m.lastErr = ""
	m.exitCode = nil
	m.mu.Unlock()
	if err := cmd.Start(); err != nil {
		return coreStatus{}, err
	}
	done := make(chan struct{})
	m.mu.Lock()
	m.cmd, m.done = cmd, done
	m.mu.Unlock()
	go m.pump(out)
	go func() {
		err := cmd.Wait()
		code := 0
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			code = ee.ExitCode()
		} else if err != nil {
			code = -1
		}
		m.mu.Lock()
		if m.cmd == cmd {
			m.exitCode = &code
		}
		m.mu.Unlock()
		close(done)
	}()
	select {
	case <-done:
		s := m.status()
		msg := s.Error
		if msg == "" {
			msg = "core exited"
		}
		return s, errors.New(msg)
	case <-time.After(1200 * time.Millisecond):
		return m.status(), nil
	}
}

func (m *coreManager) pump(r io.Reader) {
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 64*1024), 1024*1024)
	for sc.Scan() {
		m.addLog(stripANSI(sc.Text()))
	}
}

// stop 结束内核（先温和，3 秒后强制）
func (m *coreManager) stop() {
	m.mu.Lock()
	cmd, done := m.cmd, m.done
	m.cmd = nil
	m.mu.Unlock()
	if cmd == nil || cmd.Process == nil {
		return
	}
	select {
	case <-done:
		return
	default:
	}
	interrupt(cmd)
	select {
	case <-done:
	case <-time.After(3 * time.Second):
		_ = cmd.Process.Kill()
		<-done
	}
}

func stripANSI(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] == 0x1b && i+1 < len(s) && s[i+1] == '[' {
			j := i + 2
			for j < len(s) && (s[j] == ';' || (s[j] >= '0' && s[j] <= '9')) {
				j++
			}
			if j < len(s) && s[j] == 'm' {
				i = j
				continue
			}
		}
		b.WriteByte(s[i])
	}
	return b.String()
}
