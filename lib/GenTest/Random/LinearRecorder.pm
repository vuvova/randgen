package GenTest::Random::LinearRecorder;

require Exporter;
use Carp;

=pod

Low-level implementation of the pseudo-random number generator.

The important thing to note is that several pseudo-random number
generators may be active at the same time, seeded with different
values. Therefore the underlying pseudo-random function must not rely
on perlfunc's srand() and rand() because those maintain a single
system-wide pseudo-random sequence.

This module implements Linear Congruential Random Number Generator, see
http://en.wikipedia.org/wiki/Linear_congruential_generator
For efficiency, math is done in integer mode

It writes down all generated numbers in a log file.

=cut

use constant RANDOM_SEED		=> 0;
use constant RANDOM_GENERATOR		=> 1;

my $log;

sub new {
  my $class = shift;

  my $prng = bless [], $class;

  $prng->setSeed($_[0] or 1);

  return $prng;
}

sub setSeed {
  $_[0]->[RANDOM_SEED] = $_[1];
  $_[0]->[RANDOM_GENERATOR] = $_[1];
}

sub update_generator {
  use integer;
  $_[0]->[RANDOM_GENERATOR] =
  $_[0]->[RANDOM_GENERATOR] * 1103515245 + 12345;
  return ($_[0]->[RANDOM_GENERATOR] >> 15) & 0xFFFF;
}

### Random unsigned 16-bit integer
sub uint16 {
  use integer;
  my $d = $_[2] - $_[1] + 1;
  my $r = update_generator($_[0]) % $d;
  print $log pack($d > 256 ? 'S' : 'C', $r);
  return $r + $_[1];
}

### Signed 64-bit integer of any range.
### Slower, so use uint16 wherever possible.
sub int {
  my $d = $_[2] - $_[1] + 1;
  my $r = int((update_generator($_[0]) / 0x10000) * $d);
  print $log pack('q', $r);
  return $r + $_[1];
}

### Signed 64-bit float of any range.
sub float {
  # Since this may be a 64-bit platform, we mask down to 16 bit
  # to ensure the division below becomes correct.
  my $r = (update_generator($_[0]) / 0x10000) * ($_[2] - $_[1] + 1);
  print $log pack('F', $r);
  return $r + $_[1];
}

sub set_filename {
  use autodie;
  use IO::Handle;
  use GenTest::Random;
  $GenTest::Random::PRNG='LinearRecorder';
  open $log, '>', $_[0];
  autoflush $log 1;
}

1
