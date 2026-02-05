# Klipper extension: Run shell commands from gcode macros
#
# Provides [gcode_shell_command <name>] config sections and
# the RUN_SHELL_COMMAND gcode command.
#
# Copyright (C) 2025 SnapmakerU1-Extended-Firmware contributors
# Licensed under GPL-3.0
#
# Based on the community gcode_shell_command pattern for Klipper.

import subprocess
import shlex
import logging


class ShellCommand:
    def __init__(self, config):
        self.name = config.get_name().split()[-1]
        self.printer = config.get_printer()
        self.gcode = self.printer.lookup_object('gcode')
        self.command = config.get('command')
        self.timeout = config.getfloat('timeout', 2.)
        self.verbose = config.getboolean('verbose', True)
        self.gcode.register_mux_command(
            "RUN_SHELL_COMMAND", "CMD", self.name,
            self.cmd_RUN_SHELL_COMMAND,
            desc="Run shell command: %s" % self.name
        )

    def cmd_RUN_SHELL_COMMAND(self, gcmd):
        params = gcmd.get('PARAMS', '')
        # Build command as a list to avoid shell injection.
        # The configured command is split via shlex, and each PARAMS
        # token is individually quoted before being appended.
        cmd_list = shlex.split(self.command)
        if params:
            for token in shlex.split(params):
                cmd_list.append(token)
        self.gcode.respond_info("Running shell command: %s" % self.name)
        logging.info("gcode_shell_command %s: executing %s",
                     self.name, cmd_list)
        try:
            proc = subprocess.run(
                cmd_list,
                capture_output=True,
                text=True,
                timeout=self.timeout
            )
            if self.verbose:
                if proc.stdout:
                    self.gcode.respond_info(proc.stdout.rstrip())
                if proc.stderr:
                    self.gcode.respond_info("stderr: " + proc.stderr.rstrip())
            if proc.returncode != 0:
                msg = ("Shell command '%s' exited with code %d"
                       % (self.name, proc.returncode))
                self.gcode.respond_info(msg)
                logging.warning(msg)
        except subprocess.TimeoutExpired:
            msg = ("Shell command '%s' timed out after %.1fs"
                   % (self.name, self.timeout))
            self.gcode.respond_info(msg)
            logging.warning(msg)
        except Exception as e:
            msg = ("Shell command '%s' error: %s"
                   % (self.name, str(e)))
            self.gcode.respond_info(msg)
            logging.exception(msg)


def load_config_prefix(config):
    return ShellCommand(config)
