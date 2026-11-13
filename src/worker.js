// Serves the Godot web export from static assets.
//
// index.wasm is larger than the 25 MiB per-file static asset limit, so the
// build stores it gzipped (index.wasm.gz). This Worker runs only for
// /index.wasm (see run_worker_first in wrangler.jsonc) and serves the gzipped
// file with Content-Encoding: gzip; the browser decompresses it transparently.
// Everything else is served directly by the assets layer.

export default {
	async fetch(request, env) {
		const url = new URL(request.url);
		if (url.pathname === "/index.wasm") {
			const gz = await env.ASSETS.fetch(new URL("/index.wasm.gz", url), {
				headers: request.headers,
			});
			if (!gz.ok && gz.status !== 304) return gz;
			const headers = new Headers(gz.headers);
			headers.set("Content-Type", "application/wasm");
			headers.set("Content-Encoding", "gzip");
			headers.set("Cache-Control", "public, max-age=3600, must-revalidate");
			headers.delete("Content-Length");
			return new Response(gz.body, {
				status: gz.status,
				headers,
				encodeBody: "manual",
			});
		}
		return env.ASSETS.fetch(request);
	},
};
