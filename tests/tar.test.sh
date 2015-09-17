#!/bin/bash

set -u

addr=`get_listen_addr 0`
storage=`get_storage 0`
config=`get_config_slave $addr $storage`

tests_ensure run_sould "$config" true
sould_job_id=$(cat `tests_stdout`)

tests_ensure create_repository "upstream"

tests_ensure create_commit "upstream" "file_foo"

mirror_name="mirror/of/upstream"

tests_do request_tar 0 $mirror_name
tests_assert_stderr_re "404 Not Found"

tests_do request_pull 0 $mirror_name `tests_tmpdir`/upstream
tests_assert_stderr_re "201 Created"

tests_do request_tar 0 $mirror_name '>' `tests_tmpdir`/archive.tar
tests_assert_stderr_re "200 OK"
tests_assert_stderr_re "X-State: success"
tests_assert_stderr_re "X-Date:"

modify_date_header="$(grep "X-Date:" `tests_stderr`)"

tests_ensure tar -xlvf `tests_tmpdir`/archive.tar
tests_assert_stdout_re "file_foo"

tests_ensure mv `tests_tmpdir`/upstream `tests_tmpdir`/backup_upstream

# sould should return tar archive with status 'success', because should
# not make pull request to repository.
tests_do request_tar 0 $mirror_name ">" `tests_tmpdir`/archive2.tar
tests_assert_stderr_re "200 OK"
tests_assert_stderr_re "X-State: success"
tests_assert_stderr_re "$modify_date_header"

tests_ensure tar -xlvf `tests_tmpdir`/archive2.tar
tests_assert_stdout_re 'file_foo'

# but if sould will be restarted, states table will be flushed, and state will
# be 'unknown', so sould should try to make pull, but pull will be failed
# (upstream corrupted earlier), and despite this, sould should return tar
# archive of last available version and show header 'X-Date' with last
# successfull update date.

tests_stop_background $sould_job_id

tests_ensure run_sould "$config" true

tests_do request_tar 0 $mirror_name ">" `tests_tmpdir`/archive3.tar
tests_assert_stderr_re "200 OK"
tests_assert_stderr_re "X-State: failed"
tests_assert_stderr_re "$modify_date_header"

tests_ensure tar -xlvf `tests_tmpdir`/archive3.tar
tests_assert_stdout_re 'file_foo'
