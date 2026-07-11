# Rubybench

Benchmark runner for [rubybench.github.io](https://rubybench.github.io)

## Apply recipes

```bash
# dry-run
bin/hocho apply -n ruby-kai1

# apply
bin/hocho apply ruby-kai1
```

## How it works

1. ruby/docker-images builds a Docker image nightly. Each image has a date in the image name, e.g. 20250908.
2. New Ruby versions are tracked in rubies.yml within the rubybench-data repository.
3. The ruby-kai1 server runs a [systemd timer](infra/recipes/files/lib/systemd/system/rubybench.timer).
4. That timer essentially just keeps executing [bin/ruby-kai1.sh](bin/ruby-kai1.sh).
5. That script runs a benchmark, updates YAMLs, and pushes it to the rubybench-data repository with bin/sync-results.rb.
6. As soon as the YAML is pushed, https://github.com/rubybench/rubybench.github.io sees it through GitHub's raw bob.

This fork additionally benchmarks [monoruby](https://github.com/sisshiki1969/monoruby)
on the same machine so its results are comparable with the CRuby ones:
after the CRuby run, [benchmark/monoruby.rb](benchmark/monoruby.rb) builds
monoruby master (Rust toolchain required), records the benchmarked revision
in `results/monorubies.yml`, and runs the ruby-bench suite with it through
`benchmark/ruby-bench/misc/monoruby-sync.rb`, writing to
`results/monoruby-bench{,-rss}/`. The results repository and commit prefix
default to this fork and the hostname, and can be overridden with the
`RUBYBENCH_RESULTS_REPO` / `RUBYBENCH_RESULTS_COMMIT_PREFIX` environment
variables.

## Useful commands

* Stopping the timer (to avoid interferences): `sudo systemctl stop rubybench.timer`

## License

MIT License
