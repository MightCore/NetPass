USE netpass;
CREATE INDEX results_idx1 ON results (macAddress);
CREATE INDEX results_idx2 ON results (macAddress, testType);
CREATE INDEX results_idx3 ON results (macAddress, status);
CREATE INDEX config_idx1 ON config (dt);
CREATE UNIQUE INDEX pages_idx1 ON pages (name, network);
CREATE INDEX clientHistory_idx1 ON clientHistory (macAddress);
CREATE INDEX clientHistory_idx2 ON clientHistory (dt);
CREATE INDEX nessusScans_idx1 ON nessusScans (status);
CREATE INDEX snortRules_idx1 ON snortRules (status);
CREATE INDEX appStarter_idx1 ON appStarter (status);
CREATE INDEX stats_procs_idx1 ON stats_procs (dt);
CREATE INDEX stats_procs_idx2 ON stats_procs (proc);
CREATE UNIQUE INDEX urlFilters_idx1 ON urlFilters (url, network);
