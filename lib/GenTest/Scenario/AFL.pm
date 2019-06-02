# Copyright (C) 2017 MariaDB Corporation Ab
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301
# USA


########################################################################
#
# The module implements a normal upgrade scenario.
#
# This is the simplest form of upgrade. The test starts the GEN server,
# executes some flow on it, shuts down the server, starts the AFL one
# on the same datadir
#
########################################################################

package GenTest::Scenario::AFL;

require Exporter;
@ISA = qw(GenTest::Scenario);

use strict;
use DBI;
use GenTest;
use GenTest::Scenario;
use GenTest::Constants;
use GenTest::Properties;
use GenTest::App::GenTest;
use GenTest::Random::RePlayer;
use GenTest::Random::LinearRecorder;
use DBServer::MySQL::MySQLd;

sub new {
  my $class= shift;
  my $self= $class->SUPER::new(@_);

  $self->setPropertyDefaults(
    grammar => 'conf/mariadb/oltp.yy',
    gendata => 'conf/mariadb/innodb_upgrade.zz',
    duration => 300,
    queries => 1,
    threads => 1);

  return $self;
}

sub run {
  my $self= shift;
  my ($status, $genserver, $gentest, $aflserver);

  $status= STATUS_OK;

  $genserver= $self->prepareServer(1,
    {
      vardir => $self->getProperty('vardir'),
      port => $self->getProperty('port'),
      valgrind => 0,
    }
  );
  $aflserver= $self->prepareServer(2,
    {
      vardir => $self->getProperty('vardir'),
      port => $self->getProperty('port'),
      valgrind => 0,
      afl => 1,
      start_dirty => 1
    }
  );
  my $prng_file = $self->getProperty('vardir') . '/prng.dat';

  say("-- GEN server info: --");
  say($genserver->version());
  $genserver->printServerOptions();
  say("----------------------");

  #####
  $self->printStep("Starting the GEN server");
  $status= $genserver->startServer;
  return $self->finalize(STATUS_TEST_FAILURE,[$genserver]) unless $status == STATUS_OK;

  #####
  $self->printStep("Generating test data");
  $gentest= $self->prepareGentest(1,
    {
      duration => int($self->getTestDuration * 2 / 3),
      dsn => [$genserver->dsn($self->getProperty('database'))],
      servers => [$genserver],
      gendata => $self->getProperty('gendata'),
      'gendata-advanced' => $self->getProperty('gendata-advanced'),
    }
  );
  $status= $gentest->doGenData();
  return $self->finalize(STATUS_TEST_FAILURE,[$genserver]) unless $status == STATUS_OK;

  #####
  $self->printStep("Running test flow once");
  GenTest::Random::LinearRecorder::set_filename($prng_file);
  $gentest= $self->prepareGentest(1,
    {
      duration => int($self->getTestDuration * 2 / 3),
      dsn => [$genserver->dsn($self->getProperty('database'))],
      servers => [$genserver],
      'start-dirty' => 1,
    }
  );
  $status= $gentest->run();
  return $self->finalize(STATUS_TEST_FAILURE,[$genserver]) unless $status == STATUS_OK;

  #####
  $self->printStep("Stopping the GEN server");
  $status= $genserver->stopServer;
  if ($status != STATUS_OK) {
    sayError("Shutdown of the GEN server failed");
    return $self->finalize(STATUS_TEST_FAILURE,[$genserver]);
  }

  #####
  $self->printStep("Checking the GEN server log for fatal errors after shutdown");
  $status= $self->checkErrorLog($genserver, {CrashOnly => 1});
  return $self->finalize(STATUS_TEST_FAILURE,[$genserver]) unless $status == STATUS_OK;

  ####
  if (0) { # test a replay
    $self->printStep("Starting the GEN server");
    $status= $genserver->startServer;
    return $self->finalize(STATUS_TEST_FAILURE,[$genserver]) unless $status == STATUS_OK;
    $self->printStep("Running test flow once");
    GenTest::Random::RePlayer::set_filename($prng_file);
    $status= $gentest->run();
    return $self->finalize(STATUS_TEST_FAILURE,[$genserver]) unless $status == STATUS_OK;
    $self->printStep("Stopping the GEN server");
    $status= $genserver->stopServer;
    return $self->finalize(STATUS_TEST_FAILURE,[$genserver]) unless $status == STATUS_OK;
    $self->printStep("Checking the GEN server log for fatal errors after shutdown");
    $status= $self->checkErrorLog($genserver, {CrashOnly => 1});
    return $self->finalize($status,[]);
  }

  #####
  $self->printStep("starting AFL server");
  $status= $aflserver->startServer;
  return $self->finalize(STATUS_TEST_FAILURE,[$aflserver]) unless $status == STATUS_OK;

  while(1) {
    $self->printStep("Reconnecting the AFL server");
    $status = $aflserver->waitForServerToStart(1);
    return $self->finalize(STATUS_TEST_FAILURE,[$aflserver]) unless $status;
    last unless -f $prng_file;
    GenTest::Random::RePlayer::set_filename($prng_file);
    $self->printStep("Running test flow once");
    $status= $gentest->run();
    unlink $prng_file;
    return $self->finalize(STATUS_TEST_FAILURE,[$aflserver]) unless $status == STATUS_OK;
    $self->printStep("Stopping the AFL server");
    $status= $aflserver->stopServer;
    return $self->finalize(STATUS_TEST_FAILURE,[$aflserver]) unless $status == STATUS_OK;
  }
  $self->printStep("No $prng_file, exiting");
  $status= $aflserver->stopServer;
  return $self->finalize($status,[]);
}

1;
