package X12::Schema::SegmentUse;

use Moose;
use namespace::autoclean;

with 'X12::Schema::Sequencable';

has def => (is => 'ro', isa => 'X12::Schema::Segment', required => 1);

sub encode {
    my ($self, $sink, $obj) = @_;

    if (!$self->def->encode($sink, $obj) && $self->required) {
        die 'Segment '.$self->name." must contain data\n";
    }
}

sub BUILD {
    my ($self) = @_;

    # DIVERSITY: possibly worth restricting use of 'B' type here?

    # we can only be empty in the event that we are optional, but in that case
    # Sequence will automatically handle _can_be_empty and _ambiguous_end_tags.
    $self->_can_be_empty(0);
    $self->_ambiguous_end_tags({});
    $self->_initial_tags({ $self->def->tag => 1 });
}

__PACKAGE__->meta->make_immutable;
