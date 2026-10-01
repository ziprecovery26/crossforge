#!/usr/bin/env bun
/**
 * build-matrix.ts — cross-compile driver (upstream-compatible + Android/Termux target)
 *
 * Based on packages/opencode/script/build.ts (MIT, anomalyco/opencode) with additions:
 *   - `--targets=` selector so CI can build a subset
 *   - `android-arm64` target (Bun 1.4.x official `bun-linux-arm64-android` runtime)
 *   - Termux package layout assembly (binary + native libs + wrapper)
 *
 * Usage:
 *   bun run script/build-matrix.ts --targets=linux-x64,windows-x64
 *   bun run script/build-matrix.ts --targets=android-arm64 --opentui-android=./libopentui.so
 */
import { $ } from "bun"
import path from "path"
import { fileURLToPath } from "url"
import { createSolidTransformPlugin } from "@opentui/solid/bun-plugin"

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)
const dir = path.resolve(__dirname, "..")

process.chdir(dir)

const generated = await import("./generate.ts")

import { Script } from "@opencode-ai/script"
import pkg from "../package.json"

const args = process.argv.slice(2)
const hasFlag = (f: string) => args.includes(f)
const getArg = (name: string) => {
  const hit = args.find((a) => a.startsWith(`--${name}=`))
  return hit ? hit.slice(name.length + 3) : undefined
}

const sourcemapsFlag = hasFlag("--sourcemaps")
const skipInstall = hasFlag("--skip-install")
const skipEmbedWebUi = hasFlag("--skip-embed-web-ui")
const release = hasFlag("--release") || Script.release
const opentuiAndroid = getArg("opentui-android")
const plugin = createSolidTransformPlugin()

type Target = {
  id: string
  os: "linux" | "darwin" | "win32"
  arch: "arm64" | "x64"
  abi?: "musl" | "android"
  avx2?: false
}

/**
 * Master build matrix.
 * `id` is what you pass to --targets=... and also the artifact/dir name (opencode-<id>).
 */
const ALL_TARGETS: Target[] = [
  { id: "linux-x64", os: "linux", arch: "x64" },
  { id: "linux-x64-baseline", os: "linux", arch: "x64", avx2: false },
  { id: "linux-arm64", os: "linux", arch: "arm64" },
  { id: "linux-x64-musl", os: "linux", arch: "x64", abi: "musl" },
  { id: "linux-x64-musl-baseline", os: "linux", arch: "x64", abi: "musl", avx2: false },
  { id: "linux-arm64-musl", os: "linux", arch: "arm64", abi: "musl" },
  { id: "darwin-x64", os: "darwin", arch: "x64" },
  { id: "darwin-x64-baseline", os: "darwin", arch: "x64", avx2: false },
  { id: "darwin-arm64", os: "darwin", arch: "arm64" },
  { id: "windows-x64", os: "win32", arch: "x64" },
  { id: "windows-x64-baseline", os: "win32", arch: "x64", avx2: false },
  { id: "windows-arm64", os: "win32", arch: "arm64" },
  // Android / Termux (aarch64, bionic libc) — Bun 1.4.x ships an official android runtime
  { id: "android-arm64", os: "linux", arch: "arm64", abi: "android" },
]

const requested = getArg("targets")
const targets = requested
  ? ALL_TARGETS.filter((t) => requested.split(",").includes(t.id))
  : ALL_TARGETS

const missing = requested
  ? requested.split(",").filter((id) => !ALL_TARGETS.some((t) => t.id === id))
  : []
if (missing.length) {
  console.error(`unknown target(s): ${missing.join(", ")}`)
  console.error(`known: ${ALL_TARGETS.map((t) => t.id).join(", ")}`)
  process.exit(1)
}

/** bun build --compile target string */
function bunTarget(t: Target) {
  if (t.abi === "android") return `bun-linux-${t.arch}-android`
  if (t.os === "win32") return `bun-windows-${t.arch === "x64" ? "x64" : "arm64"}${t.avx2 === false ? "-baseline" : ""}`
  if (t.os === "darwin") return `bun-darwin-${t.arch === "x64" ? "x64" : "arm64"}${t.avx2 === false ? "-baseline" : ""}`
  return `bun-linux-${t.arch === "x64" ? "x64" : "arm64"}${t.avx2 === false ? "-baseline" : ""}${t.abi ? `-${t.abi}` : ""}`
}

const createEmbeddedWebUIBundle = async () => {
  console.log(`Building Web UI to embed in the binary`)
  const appDir = path.join(import.meta.dirname, "../../app")
  const dist = path.join(appDir, "dist")
  await $`OPENCODE_CHANNEL=${Script.channel} bun run --cwd ${appDir} build`
  const files = (await Array.fromAsync(new Bun.Glob("**/*").scan({ cwd: dist })))
    .map((file) => file.replaceAll("\\", "/"))
    .filter((file) => !file.endsWith(".map"))
    .sort()
  const imports = files.map((file, i) => {
    const spec = path.relative(dir, path.join(dist, file)).replaceAll("\\", "/")
    return `import file_${i} from ${JSON.stringify(spec.startsWith(".") ? spec : `./${spec}`)} with { type: "file" };`
  })
  const entries = files.map((file, i) => `  ${JSON.stringify(file)}: file_${i},`)
  return [
    `// Import all files as file_$i with type: "file"`,
    ...imports,
    `// Export with original mappings`,
    `export default {`,
    ...entries,
    `}`,
  ].join("\n")
}

let embeddedFileMap: string | null = null
if (!skipEmbedWebUi) {
  // The embedded web UI is a desktop/browser convenience; Termux builds stay lean.
  embeddedFileMap = await createEmbeddedWebUIBundle()
}
const treeSitterWorker = await Bun.file(fileURLToPath(import.meta.resolve("@opentui/core/parser.worker"))).text()

await $`rm -rf dist`

if (!skipInstall) {
  await $`bun install --os="*" --cpu="*" @opentui/core@${pkg.dependencies["@opentui/core"]}`
  await $`bun install --os="*" --cpu="*" @parcel/watcher@${pkg.dependencies["@parcel/watcher"]}`
  await $`bun install --os="*" --cpu="*" @ff-labs/fff-bun@${pkg.dependencies["@ff-labs/fff-bun"]}`
}

const binaries: Record<string, string> = {}

for (const item of targets) {
  const name = `${pkg.name}-${item.id}`
  const target = bunTarget(item)
  console.log(`\n=== building ${name} (bun target: ${target}) ===`)
  await $`mkdir -p dist/${name}/bin`

  const workerPath = "./src/cli/tui/worker.ts"
  const treeSitterWorkerPath = "opentui-tree-sitter-worker.js"
  const bunfsRoot = item.os === "win32" ? "B:/~BUN/root/" : "/$bunfs/root/"

  const result = await Bun.build({
    conditions: ["bun", "node"],
    tsconfig: "./tsconfig.json",
    plugins: [plugin],
    external: ["node-gyp"],
    format: "esm",
    minify: true,
    sourcemap: sourcemapsFlag ? "linked" : "none",
    splitting: true,
    compile: {
      autoloadBunfig: false,
      autoloadDotenv: false,
      autoloadTsconfig: true,
      autoloadPackageJson: true,
      target: target as any,
      outfile: `dist/${name}/bin/opencode`,
      execArgv: [`--user-agent=opencode/${Script.version}`, "--use-system-ca", "--"],
      windows: {},
    },
    files: {
      [treeSitterWorkerPath]: treeSitterWorker,
      ...(embeddedFileMap && item.abi !== "android" ? { "opencode-web-ui.gen.ts": embeddedFileMap } : {}),
    },
    entrypoints: [
      "./src/index.ts",
      workerPath,
      treeSitterWorkerPath,
      ...(embeddedFileMap && item.abi !== "android" ? ["opencode-web-ui.gen.ts"] : []),
    ],
    define: {
      FFF_LIBC: JSON.stringify(item.abi === "musl" ? "musl" : item.abi === "android" ? "bionic" : "gnu"),
      OPENCODE_VERSION: `'${Script.version}'`,
      OPENCODE_MODELS_DEV: generated.modelsData,
      OTUI_TREE_SITTER_WORKER_PATH: bunfsRoot + treeSitterWorkerPath,
      OPENCODE_WORKER_PATH: workerPath,
      OPENCODE_CHANNEL: `'${Script.channel}'`,
      OPENCODE_LIBC: item.os === "linux" ? `'${item.abi ?? "glibc"}'` : "",
      ...(item.os === "linux" ? { "process.env.OPENTUI_LIBC": JSON.stringify(item.abi === "android" ? "glibc" : item.abi ?? "glibc") } : {}),
    },
  })
  if (!result.success) {
    console.error(result.logs)
    process.exit(1)
  }

  if (item.os === "darwin" && process.platform === "darwin") {
    await $`codesign --force --sign - dist/${name}/bin/opencode`
  }

  // Smoke test: only run if binary is for current platform
  if (item.os === process.platform && item.arch === process.arch && !item.abi) {
    const binaryPath = `dist/${name}/bin/opencode`
    console.log(`Running smoke test: ${binaryPath} --version`)
    try {
      const versionOutput = await $`${binaryPath} --version`.text()
      console.log(`Smoke test passed: ${versionOutput.trim()}`)
    } catch (e) {
      console.error(`Smoke test failed for ${name}:`, e)
      process.exit(1)
    }
  }

  // ---- Android/Termux packaging layout -------------------------------------
  // Termux bionic libc expects a bash launcher so we can set LD_LIBRARY_PATH
  // before exec'ing the real (statically-compiled-by-Bun) binary.
  //
  //   dist/opencode-android-arm64/
  //     bin/opencode        <- bash wrapper (PATH-friendly)
  //     bin/opencode.bin    <- the actual compiled binary
  //     lib/libopentui.so   <- TUI renderer native lib (built with the NDK)
  if (item.abi === "android") {
    const outDir = `dist/${name}`
    await $`mv ${outDir}/bin/opencode ${outDir}/bin/opencode.bin`
    await $`chmod +x ${outDir}/bin/opencode.bin`

    if (opentuiAndroid) {
      await $`mkdir -p ${outDir}/lib`
      await $`cp ${opentuiAndroid} ${outDir}/lib/libopentui.so`
      console.log(`bundled libopentui.so -> ${outDir}/lib/libopentui.so`)
    } else {
      console.warn(
        `WARNING: no --opentui-android=... supplied. The Android binary will run but the TUI will fail\n` +
          `         to load libopentui.so. Build it with android/opentui/build-opentui-android.sh.`,
      )
    }

    await Bun.write(
      `${outDir}/bin/opencode`,
      `#!/data/data/com.termux/files/usr/bin/bash
# CrossForge Termux launcher — resolves the bundled native libs, then runs the binary.
set -e
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
PREFIX_DIR="\${PREFIX:-/data/data/com.termux/files/usr}"
LIB_DIR="$SELF_DIR/../lib"
BIN="$SELF_DIR/opencode.bin"
[ -x "$BIN" ] || BIN="$(command -v opencode.bin || true)"
export LD_LIBRARY_PATH="$LIB_DIR:$PREFIX_DIR/lib:\${LD_LIBRARY_PATH:-}"
export OPENTUI_LIB_PATH="\${OPENTUI_LIB_PATH:-$LIB_DIR}"
exec "$BIN" "$@"
`,
    )
    await $`chmod +x ${outDir}/bin/opencode`
  }

  await $`rm -rf ./dist/${name}/bin/tui`
  await Bun.write(
    `dist/${name}/package.json`,
    JSON.stringify(
      {
        name,
        version: Script.version,
        preferUnplugged: true,
        os: [item.os],
        cpu: [item.arch],
        ...(item.abi ? { libc: [item.abi] } : {}),
      },
      null,
      2,
    ),
  )
  binaries[name] = Script.version
}

if (release) {
  console.log("\n=== packaging archives ===")
  for (const key of Object.keys(binaries)) {
    if (key.includes("windows")) {
      await $`zip -r ../../${key}.zip *`.cwd(`dist/${key}/bin`)
    } else if (key.includes("android")) {
      await $`tar -czf ../../${key}.tar.gz *`.cwd(`dist/${key}`)
    } else {
      await $`tar -czf ../../${key}.tar.gz *`.cwd(`dist/${key}/bin`)
    }
  }
}

console.log(`\nbuilt ${Object.keys(binaries).length} target(s): ${Object.keys(binaries).join(", ")}`)
export { binaries }
