const http = require("http");
const fs = require("fs");
const path = require("path");

const rootDir = process.argv[2];
const port = Number(process.argv[3] || "4173");

if (!rootDir) {
  console.error("Missing root dir argument.");
  process.exit(2);
}

if (!fs.existsSync(rootDir)) {
  console.error(`SWAR_WEB_ROOT not found: ${rootDir}`);
  process.exit(2);
}

const mime = new Map([
  [".html", "text/html; charset=utf-8"],
  [".js", "text/javascript; charset=utf-8"],
  [".mjs", "text/javascript; charset=utf-8"],
  [".css", "text/css; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".wasm", "application/wasm"],
  [".pck", "application/octet-stream"],
  [".png", "image/png"],
  [".jpg", "image/jpeg"],
  [".jpeg", "image/jpeg"],
  [".svg", "image/svg+xml; charset=utf-8"],
  [".ico", "image/x-icon"],
  [".txt", "text/plain; charset=utf-8"],
]);

function safePath(urlPath) {
  const decoded = decodeURIComponent(urlPath.split("?")[0]);
  const rel = decoded === "/" ? "/index.html" : decoded;
  const abs = path.resolve(rootDir, "." + rel);
  if (!abs.startsWith(path.resolve(rootDir))) return null;
  return abs;
}

const server = http.createServer((req, res) => {
  const abs = safePath(req.url || "/");
  if (!abs) {
    res.statusCode = 400;
    res.end("Bad path");
    return;
  }

  fs.readFile(abs, (err, data) => {
    if (err) {
      res.statusCode = 404;
      res.end("Not found");
      return;
    }
    const ext = path.extname(abs).toLowerCase();
    res.setHeader("Content-Type", mime.get(ext) || "application/octet-stream");
    res.end(data);
  });
});

server.listen(port, "127.0.0.1", () => {
  console.log(`[e2e] Serving ${rootDir} on http://127.0.0.1:${port}`);
});

