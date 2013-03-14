package X12::Schema::Sequencable;

use Moose::Role;
use namespace::autoclean;

has name     => (isa => 'Str', is => 'ro', required => 1);
has required => (isa => 'Bool', is => 'ro');
has max_use  => (isa => 'Maybe[Int]', is => 'ro', default => 1);

# these should be set at BUILD
has _can_be_empty => (isa => 'Bool', is => 'rw', init_arg => undef);
has _initial_tags => (isa => 'HashRef', is => 'rw', init_arg => undef);
has _ambiguous_end_tags => (isa => 'HashRef', is => 'rw', init_arg => undef);

requires qw( encode );

1;
