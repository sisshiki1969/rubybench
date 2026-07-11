#!/usr/bin/env ruby
# frozen_string_literal: true

# Builds monoruby master and runs the ruby-bench suite with it on this
# machine, writing results into results/ (the rubybench-data checkout)
# via benchmark/ruby-bench/misc/monoruby-sync.rb:
#
#   results/monoruby-bench/<benchmark>.yml     mean iteration time (ms)
#   results/monoruby-bench-rss/<benchmark>.yml RSS (MiB)
#   results/monorubies.yml                     date => benchmarked revision
#
# Like lib/ruby_bench.rb, this is idempotent per day so the systemd timer
# can keep executing it: it exits early when today's results already exist.
#
# Environment variables:
#   MONORUBY_REPO          git repository to clone monoruby from
#   MONORUBY_DIR           monoruby checkout/build directory
#   MONORUBY_BENCH_TIMEOUT timeout for the whole suite in seconds
#   MONORUBY_SYNC_ARGS     extra arguments for monoruby-sync.rb (e.g. --excludes=x,y)

require 'rbconfig'
require 'shellwords'
require 'yaml'

ROOT = File.expand_path('..', __dir__)
RESULTS_DIR = File.join(ROOT, 'results')
MONORUBY_REPO = ENV.fetch('MONORUBY_REPO', 'https://github.com/sisshiki1969/monoruby.git')
MONORUBY_DIR = File.expand_path(ENV.fetch('MONORUBY_DIR', File.join(ROOT, 'monoruby')))
SYNC_SCRIPT = File.join(ROOT, 'benchmark/ruby-bench/misc/monoruby-sync.rb')

date = Time.now.utc.strftime('%Y%m%d').to_i

# Skip if monoruby is already benchmarked for today
latest = Dir.glob(File.join(RESULTS_DIR, 'monoruby-bench', '*.yml'))
  .flat_map { |file| YAML.load_file(file).keys }.max
if latest && latest >= date
  puts "monoruby is already benchmarked for #{latest}"
  exit 0
end

unless File.exist?(SYNC_SCRIPT)
  abort "ERROR: #{SYNC_SCRIPT} not found. " \
        "Run `git submodule update --init benchmark/ruby-bench` with a ruby-bench that has harness-monoruby"
end

# Fetch and build the latest monoruby master
if File.directory?(File.join(MONORUBY_DIR, '.git'))
  system('git', '-C', MONORUBY_DIR, 'fetch', '--depth', '1', 'origin', 'master', exception: true)
  system('git', '-C', MONORUBY_DIR, 'reset', '--hard', 'FETCH_HEAD', exception: true)
else
  system('git', 'clone', '--depth', '1', MONORUBY_REPO, MONORUBY_DIR, exception: true)
end
system('cargo', 'build', '--release', chdir: MONORUBY_DIR, exception: true)
revision = IO.popen(['git', '-C', MONORUBY_DIR, 'rev-parse', 'HEAD'], &:read).strip

# Record the revision that is actually benchmarked for this date. The
# add-monoruby workflow in rubybench-data records master HEAD via the API
# daily, but the revision built here is authoritative.
monorubies_path = File.join(RESULTS_DIR, 'monorubies.yml')
monorubies = File.exist?(monorubies_path) ? YAML.load_file(monorubies_path) || {} : {}
monorubies[date] = revision
File.write(monorubies_path, YAML.dump(monorubies.sort_by(&:first).to_h))
puts "monoruby revision: #{revision}"

# Run the suite and write results/monoruby-bench{,-rss}/. Benchmarks that
# monoruby cannot run fail inside run_benchmarks.rb and are skipped.
timeout = ENV.fetch('MONORUBY_BENCH_TIMEOUT', (4 * 60 * 60).to_s)
cmd = [
  'timeout', '--signal=KILL', timeout,
  RbConfig.ruby, SYNC_SCRIPT,
  "--monoruby=#{File.join(MONORUBY_DIR, 'target/release/monoruby')}",
  "--data=#{RESULTS_DIR}",
  "--date=#{date}",
  '--no-sudo',
  *ENV.fetch('MONORUBY_SYNC_ARGS', '').shellsplit,
]
puts "+ #{cmd.shelljoin}"
exit(system(*cmd) ? 0 : 1)
