package X12::Schema::Segment;

use Moose;
use namespace::autoclean;

has tag          => (isa => 'Str', is => 'ro', required => 1);
has friendly     => (isa => 'Str', is => 'ro', required => 1);
has constraints  => (isa => 'ArrayRef[X12::Schema::Constraint]', is => 'ro', default => sub { [] });
has elements     => (isa => 'ArrayRef[X12::Schema::Element]', is => 'ro', required => 1);
has incomplete   => (isa => 'Bool', is => 'ro', default => 0);

sub encode {
    my ($self, $sink, $obj) = @_;

    die 'Segment '.$self->friendly." must be encoded using a HASH\n" unless $obj && ref($obj) eq 'HASH' && !blessed($obj);

    for my $c ( @{ $self->constraints } ) {
        if ( () = $c->check($obj) ) {
            die $c->describe . "\n";
        }
    }

    my %tmp = %$obj;
    my @bits;

    for my $elem (@{ $self->elements }) {
        my $value = delete $tmp{ $elem->name };

        if (defined $value) {
            push @bits, $elem->encode($sink, $value);
        } else {
            if ($elem->required) {
                die "Segment ".$self->friendly." element ".$elem->name." is required";
            }

            push @bits, '';
        }
    }

    die "Excess fields for segment ".$self->friendly.": ".join(', ', sort keys %tmp)."\n" if %tmp;
    pop @bits while @bits && $bits[-1] eq '';

    die "Segment ".$self->friendly." must contain data if it is present\n" unless @bits;

    $sink->segment( join($sink->element_sep, $self->tag, @bits) . $sink->segment_term );
}

# DIVERSITY: log errors for 997/999/CONTROL, compound elements, repeated elements

# assumes that the lookahead tag has already been validated
sub decode {
    my ($self, $src) = @_;

    my $tokens = $src->get;

    my $i = $src->segment_counter;
    die "Malformed segment tag at $i\n" if @{$tokens->[0]} != 1 or @{$tokens->[0][0]} != 1;
    die "Segment with nothing but a terminator at $i\n" if @$tokens == 1;

    my %data;

    my $j = 1;

    for my $el (@{ $self->elements }) {
        my $inp = $j < @$tokens ? $tokens->[$j] : [['']];
        my $name = $el->name;

        die "Element repetition unsupported at $i\n" if @$inp != 1;
        die "Composite elements unsupported at $i\n" if @{$inp->[0]} != 1;

        $inp = $inp->[0][0];

        if ($inp eq '') {
            die "Required element $name is missing at $i\n" if $el->required;
            $data{ $name } = undef;
        } else {
            my ($err, $parsed) = $el->decode($src, $inp);

            die "Element $name is invalid ($err) at $i\n" if $err;
            $data{ $name } = $parsed;
        }

        $j++;
    }

    if ($tokens->[-1][0][0] eq '') {
        die "Illegal trailing empty element at $i\n";
    }

    if ($j < @$tokens) {
        die "Too many data elements at $i\n";
    }

    for my $c ( @{ $self->constraints } ) {
        if ( () = $c->check(\%data) ) {
            die $c->describe . " at $i\n";
        }
    }

    return \%data;
}

__PACKAGE__->meta->make_immutable;
