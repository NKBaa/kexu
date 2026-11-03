"""本地 WebDAV 服务器（仅供端到端测试）。

用 WsgiDAV 起一个最小可用的 WebDAV 服务，用于验证 App 的 WebDAV 同步适配器
在**真实 HTTP 协议**下能正确完成：目录创建(MKCOL)、上传(PUT)、
元信息查询(PROPFIND)、下载(GET)。

用法：
    python tooling/webdav-server.py --root C:\\dev\\davroot --port 8765

依赖：pip install wsgidav cheroot
"""
import argparse
import os
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=os.path.join(os.getcwd(), "davroot"))
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()

    os.makedirs(args.root, exist_ok=True)

    try:
        from wsgidav.wsgidav_app import WsgiDAVApp
        from cheroot import wsgi
    except ImportError:
        print("缺少依赖，请先执行: pip install wsgidav cheroot", file=sys.stderr)
        return 2

    config = {
        "host": args.host,
        "port": args.port,
        "provider_mapping": {"/": args.root},
        # 测试用匿名访问：鉴权逻辑由单元测试覆盖，
        # 这里聚焦「协议能否真正互通」。
        "http_authenticator": {
            "domain_controller": None,
            "accept_basic": True,
            "accept_digest": False,
            "default_to_digest": False,
        },
        "simple_dc": {"user_mapping": {"*": True}},
        "verbose": 0,
    }

    app = WsgiDAVApp(config)
    server = wsgi.Server((args.host, args.port), app)
    print(f"WebDAV listening on http://{args.host}:{args.port}/")
    print(f"root = {args.root}")
    sys.stdout.flush()
    try:
        server.start()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
