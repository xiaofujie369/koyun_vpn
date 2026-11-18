//go:build !windows

// 非 Windows 平台只用于测试：koyun-service serve <sing-box> <数据目录>，打印连接信息后一直运行
package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
)

func main() {
	if len(os.Args) != 4 || os.Args[1] != "serve" {
		fmt.Fprintln(os.Stderr, "usage: koyun-service serve <sing-box> <data-dir>")
		os.Exit(2)
	}
	core := &coreManager{binary: os.Args[2], dataDir: os.Args[3]}
	l, port, err := listenLocal()
	if err != nil {
		panic(err)
	}
	api := &apiServer{core: core, token: newToken(), host: fmt.Sprintf("127.0.0.1:%d", port)}
	_ = json.NewEncoder(os.Stdout).Encode(stateFile{Port: port, Token: api.token, Version: serviceVersion})
	panic(http.Serve(l, api))
}
