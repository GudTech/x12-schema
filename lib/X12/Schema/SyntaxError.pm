package X12::Schema::SyntaxError;

use Moose;
use namespace::autoclean;

has code => (is => 'ro', isa => 'Str', required => 1);
has message => (is => 'ro', isa => 'Str', required => 1);

__PACKAGE__->meta->make_immutable;
