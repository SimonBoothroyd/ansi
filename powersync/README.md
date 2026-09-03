# `powersync/` — the CLI's project directory, and nothing else

`powersync@0.10.0` refuses `validate` / `deploy sync-config` unless a project
directory exists (`Directory "powersync" not found. Run powersync init cloud …`),
even when `--sync-config-file-path` names the file to deploy. This directory is
that scaffold, cut down to the one file the CLI reads to know the project type:

- `cli.yaml` — `type: cloud`.

Deliberately **not** here: `service.yaml` (instance name, region, replication,
client auth). That file drives a full `powersync deploy`, which would rewrite
the cloud instance's configuration; our workflow deploys **sync config only**
(`deploy sync-config`, docs/release.md §4.2) and the instance itself stays
dashboard-managed (docs/cloud-setup.md §3). The sync rules live in
`docker/powersync-cloud.streams.yaml` next to the local `docker/powersync.yaml`
they are drift-checked against (`scripts/check_stream_drift.sh`).

Proven 2026-09-03: with only `cli.yaml` present, `deploy sync-config` proceeds
straight to the token + instance check, and `validate --validate-only
sync-config` validates the streams file alone; an unscoped `validate` also
runs the configuration-schema and connection tests, which need the
`service.yaml` we leave out (deploy runs 33702716396 and 33703880935, step 4).
