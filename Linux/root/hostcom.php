#!/usr/bin/php
<?php
	declare(ticks=1); // to be able to handle signals
	error_reporting(E_ALL);
	require_once(dirname(__FILE__) . "vmclient.class.php");
	class FatalException extends Exception {
	}

	$processes = []; // child processes
	$signal_queue = [];
	_log("started");
	$interrupted = false;
	$clients = [];
	while (true) {
		try {
			if (!pcntl_signal(SIGCHLD, "childSignal"))
				throw new FatalException("Failed to register signal handler");
			main();
			break;
		} catch (FatalException $ex) {
			_log("Fatal error: " . $ex->getMessage());
			break;
		} catch (Exception $ex) {
			_log("Error: " . $ex->getMessage());
			_log("Attempting in 5 seconds...");
			mysleep(5);
		}
	}

	function mysleep($n) {
		$time = time();
		while (time() - $time < $n) {
			sleep(1);
		}
	}

	function main() {
		global $processes, $signal_queue, $interrupted, $clients;
		$clientId = 1;
		$clients[$clientId] = new VMClient(false, $clientId); $clientId++;
		$clients[$clientId] = new VMClient(true, $clientId); $clientId++;
		$stop = [];
		$w = null;
		$e = null;
		while (true) {
			$r = [];
			foreach ($clients as $cId => $c) $r[] = $c->in;
			if (!count($r)) throw new FatalException("No clients?");
			$interrupted = false;
			$n = @stream_select($r, $w, $e, 1);
			if ($n === false) {
				$r = error_get_last();
				if ($interrupted) continue;
				throw new FatalException("run Select failed " . ($r ? $r["message"] : posix_get_last_error()));
			}
			if ($n == 0) $r = [null];
			foreach ($r as $f) {
				foreach ($clients as $c) {
					$res = $c->process($f);
					if ($res === 1) {
						if ($c->isSrv) $clients[$clientId] = new VMClient(true, $clientId); $clientId++;
						break;
					}
					if ($res === 2) {
						foreach ($processes as $pid) {
							posix_kill($pid, SIGHUP);
						}
						break;
					}
					if ($res === true) break;
					if ($res === null) {
						$stop[] = $c;
						break;
					}
					if ($f !== null) {
						if ($res === false) continue;
						$a = explode(" ", $res);
						if ($a[0] == "newshell") {
							$args = [];
							if (count($a) > 1) {
								$args[] = "--cookie";
								$args[] = $a[1];
							}
							$pid = pcntl_fork();
							if ($pid == -1) throw new FatalException("Failed to fork");
							if ($pid) {
								$processes[$pid] = $pid;
								if (isset($signal_queue[$pid])) {
									childSignal(SIGCHLD, null, $pid, $signal_queue[$pid]);
									unset($signal_queue[$pid]);
								}
								continue;
							}
							foreach ($clients as $c) $c->stop();
							pcntl_exec("/bin/vsockshell", $args);
						}
						if ($res == "shutdown") {
							throw new FatalException("Shutdown");
						}
						_log("bad command {$res}");
						break;
					}
				}
			}
			if (count($stop)) {
				foreach ($stop as $c) {
					unset($clients[$c->id]);
					$c->stop();
				}
				$stop = [];
			}
		}
	}

	function _log($msg) {
		echo "hostcom: {$msg}\n";
	}

	function childSignal($signo, $siginfo = null, $pid = null, $status = null) {
		global $processes, $signal_queue, $interrupted, $clients;
		$interrupted = true;
		if (!$pid) $pid = pcntl_waitpid(-1, $status, WNOHANG);
		while ($pid > 0) {
			//_log("PID died {$pid}");
			if ($pid && isset($processes[$pid])) {
				_log("Child finished with status {$status}");
				foreach ($clients as $c) {
					fwrite($c->out, "endtty {$pid} {$status}\n");
				}
				unset($processes[$pid]);
			} else {
				$signal_queue[$pid] = $status;
			}
			$pid = pcntl_waitpid(-1, $status, WNOHANG);
		}
		
		return true;
	}
?>