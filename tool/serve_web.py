"""build/web 을 같은 와이파이의 폰에서 열 수 있게 띄운다. 캐시를 끄고 보낸다.

    python tool/serve_web.py [포트]

브라우저가 예전 main.dart.js·아이콘 글꼴을 들고 있으면 새 빌드가 옛 화면이나 빈 아이콘으로
보인다(실제로 겪었다). 그래서 매 요청에 no-store 를 붙인다.
"""
import functools
import http.server
import os
import sys


class NoCache(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, must-revalidate")
        super().end_headers()


port = int(sys.argv[1]) if len(sys.argv) > 1 else 8762
root = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "build", "web")
http.server.ThreadingHTTPServer(("0.0.0.0", port), functools.partial(NoCache, directory=root)).serve_forever()
