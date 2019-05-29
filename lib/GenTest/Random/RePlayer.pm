package GenTest::Random::RePlayer;

require Exporter;
use Carp;

=pod

Low-level implementation of the pseudo-random number generator.

This module does not generate anything, it reads numbers from the log file,
that was generated earlier by LinearRecorder.

=cut

my $log;

sub new {
  my $class = shift;
  my $prng = bless [], $class;
  return $prng;
}

sub setSeed {
}

sub uint16 {
  use integer;
  my $d = $_[2] - $_[1] + 1;
  my $buf;
  read $log, $buf, $d > 256 ? 2 : 1;
  my $r = defined $buf ? unpack($d > 256 ? 'S' : 'C', $buf) : 0;
  return $r % $d + $_[1];
}

sub int {
  use integer;
  my $d = $_[2] - $_[1] + 1;
  my $buf;
  read $log, $buf, 8;
  my $r = defined $buf ? unpack('q', $buf) : 0;
  return $r % $d + $_[1];
}

use constant F_SIZE => defined pack 'F', 0e0;
sub float {
  my $d = $_[2] - $_[1] + 1;
  my $buf;
  read $log, $buf, F_SIZE;
  my $r = defined $buf ? unpack('F', $buf) : 0;
  $r -= $d*int($r/$d) if $r > $d;
  return $r + $_[1];
}

sub set_filename {
  use autodie;
  use GenTest::Random;
  $GenTest::Random::PRNG='RePlayer';
  open $log, '<', $_[0];
}

1
