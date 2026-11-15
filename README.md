# setup-jpm

Installs [jpm](https://github.com/java-package-manager/jpm), the Java package manager and build tool, in a GitHub
Actions job, and caches what it downloads.

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: java-package-manager/setup-jpm@v1
  - run: jpm install --frozen
  - run: jpm test
  - run: jpm build
```

No `setup-java` step is needed: jpm installs the JDK the project's `project.jsonc` asks for.

## Inputs

| Input | Default | |
|---|---|---|
| `version` | `latest` | `latest` (the newest release), `canary` (the newest build of jpm's main branch), or a version such as `0.6.0` |
| `java` | | A JDK to install and put on `PATH` as `JAVA_HOME`, such as `21`, `temurin-21` or `graalvm-21`. Only needed to run `java` yourself before jpm does |
| `cache` | `true` | Cache jpm's Maven packages, Git mirrors and builds and JDKs between runs, keyed by every `project.lock` and `project.jsonc` |
| `shims` | `false` | Install jpm's `java`, `javac`, ... shims, so plain `java` commands use the JDK the project asks for |

## Outputs

| Output | |
|---|---|
| `version` | The installed jpm version, e.g. `0.6.0` or `0.6.0-99ebfc3` |
| `path` | The path of the `jpm` binary |
| `java-home` | The JDK installed for the `java` input |

## What it does

It downloads the jpm binary for the runner (Linux and macOS on x64 and arm64, Windows on x64) from jpm's
GitHub releases, checks it against the release's `SHA256SUMS`, and puts `jpm` and `jvm` on `PATH`. It sets
`JPM_HOME` and `JPM_NO_UPDATE_CHECK=1`, so jobs do not ask GitHub for newer jpm versions. Nothing is
compiled and no JavaScript runs: it is a composite action around one shell script.

## Examples

Several platforms and JDKs, with the project choosing its JDK:

```yaml
jobs:
  build:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: java-package-manager/setup-jpm@v1
      - run: jpm test --frozen
```

Native builds with GraalVM:

```yaml
      - uses: java-package-manager/setup-jpm@v1
      - run: jpm build --native
```

Publishing with the [jpm-publish](https://github.com/java-package-manager/jpm-publish) extension:

```yaml
      - uses: java-package-manager/setup-jpm@v1
      - run: jpm add -g github:java-package-manager/jpm-publish
      - run: |
          printf '%s' "$SIGNING_KEY" > "$RUNNER_TEMP/signing.asc"
          jpm publish central
        env:
          SIGNING_KEY: ${{ secrets.SIGNING_KEY }}            # the ASCII-armored private key
          JPM_SIGNING_KEY_FILE: ${{ runner.temp }}/signing.asc
          JPM_SIGNING_PASSWORD: ${{ secrets.SIGNING_PASSWORD }}
          JPM_PUBLISH_CENTRAL_USERNAME: ${{ secrets.CENTRAL_USERNAME }}
          JPM_PUBLISH_CENTRAL_PASSWORD: ${{ secrets.CENTRAL_PASSWORD }}
```

## Versions

Releases are tagged `v1.2.3`, and `v1` follows the newest `1.x`. Use `@v1` to get fixes without
breaking changes, or `@v1.2.3` to pin one release.

To release, change `VERSION` and push to `main`: once every test passes, CI tags the commit `v<VERSION>`,
creates the GitHub release and moves the major tag (`v1`) to it. A version is never released twice;
versions like `1.3.0-rc1` become pre-releases and do not move the major tag.

## License

MIT, see [LICENSE](LICENSE).
