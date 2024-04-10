<?php
	class VMClient {
		public $isSrv;
		public $id;
		private $name;
		public $line = "";
		public $state = 0;
		public $in;
		public $out;
		private $p;
		private $pid;

		function __construct($isSrv, $clientId) {
			//parent::__construct();
			$this->isSrv = $isSrv;
			$this->id = $clientId;


			$this->pipes = [];
			$dspec = [
				0 => ["pipe", "r"],
				1 => ["pipe", "w"],
				2 => ["file", "/dev/null", "a"]
				//2 => ["file", "/vsock.log", "a"]
			];
			$this->p = $p = proc_open("/bin/vsockcom" . ($this->isSrv ? " 1" : ""), $dspec, $pipes);
			if (!$p) throw new FatalException("Failed to open ncat");
			$ps = proc_get_status($p);
			$this->pid = $ps["pid"];
			$this->name = ($isSrv ? "S" : "C") . "{$this->id} {$this->pid}";
			$status = 0;
			pcntl_waitpid($this->pid, $status, WNOHANG);
			$this->out = $pipes[0];
			$this->in = $pipes[1];
			if (!stream_set_blocking($this->in, false)) throw new FatalException("Failed to set non-blocking mode on stdin");
		}

		function stop() {
			fclose($this->out);
			fclose($this->in);
			proc_close($this->p);
		}

		function processCmd() {
			if ($this->state == 0) {
				if ($this->line != "connected") return null;
				fwrite($this->out, "command\n");
				$this->state = 1;
				return 1;
			}
			if ($this->state == 1) {
				if ($this->line != "OK") {
					$this->log("Got bad response: {$this->line}");
					return null;
				}
				echo "In command\n";
				$this->state = 2;
				return 2;
			}
			return $this->line;
		}

		function log($msg) {
			_log("[{$this->name}]: $msg");
		}

		function process($f) {
			if ($f === 0) return false;
			if ($f !== $this->in) return false;
			$sz =& $this->line;
			$first = true;
			while (true) {
				$c = fread($f, 1);
				if ($c === false || strlen($c) === 0) {
					if ($first) return null;
					$first = false;
					break;
				}
				if ($c == "\r") continue;
				if ($c == "\n") {
					$res = $this->processCmd();
					$sz = "";
					return $res;
				}
				$sz .= $c;
			}
			return true;
		}
	}
