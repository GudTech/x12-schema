package X12::Schema::TokenSource;

use Moose;
use namespace::autoclean;

has buffer => (is => 'bare', isa => 'Str', default => '');
has filler => (is => 'ro', isa => 'CodeRef', default => sub { sub { 0 } });

has _lookahead => (is => 'bare', isa =>'ArrayRef', init_arg => undef);
has _segment_re => (is => 'bare', isa =>'RegexpRef', init_arg => undef);
has _suffix_re => (is => 'bare', isa =>'RegexpRef', init_arg => undef);

has [qw(_segment_term _component_sep _repeat_sep _segment_term_suffix _element_sep)] => (is => 'bare', isa => 'Str', init_arg => undef);

has isa11_is_repeat_sep => (is => 'ro', isa => 'Bool', default => 0);

sub _parse {
    my ($self) = @_;

    if (substr($self->{buffer},0,3) eq 'ISA') {
        return if length($self->{buffer}) < 109; # ISA itself is 106 chars, but we need to see the beginning of GE to get the separator

        my $ISA = substr($self->{buffer},0,106,"");

        $self->{_element_sep} = substr($ISA, 3, 1);
        $self->{_repeat_sep} = $self->{isa11_is_repeat_sep} ? substr($ISA, 82, 1) : undef;
        $self->{_component_sep} = substr($ISA, 104, 1);
        $self->{_segment_term} = substr($ISA, 105, 1);
        ($self->{_segment_term_suffix}) = ($self->{buffer} =~ s/^(\r?\n?)//);

        $self->_delims_changed;

        # not quite a regular segment: values may include the component separator

        return [ map [[$_]], split /\Q$self->{_element_sep}/, substr($ISA,0,105) ];
    }

    # DIVERSITY: UNx, BIN, BDS segments, maybe X12.58 but I don't have a clear idea what that entails

    my ($segment) = $self->{buffer} =~ s/$self->{_segment_re}// or return;

    # DIVERSITY: EDIFACT release characters

    my ($csep, $rsep, $esep) = @$self{qw( _component_sep _repeat_sep _element_sep )};

    return [
        map [
            map [ split /\Q$csep/, $_ ],
            (defined($rsep) ? split /\Q$rsep/, $_ : $_)
        ], split /\Q$esep/, $segment
    ];
}

sub _delims_changed {
    my ($self) = @_;

    my $t = $self->{_segment_term};
    my $ts = $self->{_segment_term_suffix};
    $self->{_segment_re} = "^([^\Q$t\E]*)\Q$t$ts\E";
}

sub get {
    my ($self) = @_;

    return delete $self->{_lookahead} if $self->{_lookahead};

    my $res;

    while (1) {
        $res = $self->_parse and return $res;
        $self->filler->() or return ();
    }
}

sub peek {
    my ($self) = @_;

    return $self->{_lookahead} if $self->{_lookahead};

    my $res;

    while (1) {
        $res = $self->_parse and return $self->{_lookahead} = $res;
        $self->filler->() or return ();
    }
}

__PACKAGE__->meta->make_immutable;
