package X12::Schema::SegmentUse;

use Moose;
use namespace::autoclean;

with 'X12::Schema::Sequencable';

has def => (is => 'ro', isa => 'X12::Schema::Segment', required => 1, handles => ['encode']);

sub BUILD {
    my ($self) = @_;

    # DIVERSITY: possibly worth restricting use of 'B' type here?

    $self->_can_be_empty(0);
    $self->_ambiguous_end_tags({});
    $self->_initial_tags({ $self->def->tag => 1 });
}

__PACKAGE__->meta->make_immutable;
