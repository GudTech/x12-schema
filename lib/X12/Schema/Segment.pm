package X12::Schema::Segment;

use Moose;
use namespace::autoclean;

with 'X12::Schema::Sequencable';

has tag          => (isa => 'Str', is => 'ro', required => 1);
has syntax_notes => (isa => 'ArrayRef[X12::Schema::SyntaxNote]', is => 'ro', default => sub { [] });
has elements     => (isa => 'ArrayRef[X12::Schema::Element]', is => 'ro', required => 1);

sub encode {
    my ($self, $sink, $obj) = @_;

    die 'Segment '.$self->name." must be encoded using a HASH\n" unless $obj && ref($obj) eq 'HASH' && !blessed($obj);

    $_->check($obj) for @{ $self->syntax_notes };

    my %tmp = %$obj;
    my @bits;

    for my $elem (@{ $self->elements }) {
        my $value = delete $tmp{ $elem->name };

        if (defined $value) {
            push @bits, $elem->encode($sink, $value);
        } else {
            if ($elem->required) {
                die "Segment ".$self->name." element ".$elem->name." is required";
            }

            push @bits, '';
        }
    }

    die "Excess fields for segment ".$self->name.": ".join(', ', sort keys %tmp) if %tmp;
    pop @bits while @bits && $bits[-1] eq '';

    $sink->segment( join($sink->{element_sep}, $self->tag, @bits) . $sink->{segment_sep} ) if @bits;
}

sub BUILD {
    my ($self) = @_;

    # This needs a little elaboration.  Yes, we sometimes do not output a value.
    # But this flag only controls reading, and on read, entirely empty segments
    # should be suppressed.  If a segment is required, it needs to have at least
    # one required element.
    $self->_can_be_empty(0);

    $self->_ambiguous_end_tags({});
    $self->_initial_tags({ $self->tag => 1 });
}

__PACKAGE__->meta->make_immutable;
