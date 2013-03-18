package X12::Schema::TokenSource;

use Moose;
use namespace::autoclean;

has buffer => (is => 'bare', isa => 'Str', default => '');
has filler => (is => 'ro', isa => 'CodeRef', default => sub { sub { 0 } });

has _lookahead => (is => 'bare', isa =>'ArrayRef', init_arg => undef);
has _segment_re => (is => 'bare', isa =>'RegexpRef', init_arg => undef);
has _suffix_re => (is => 'bare', isa =>'RegexpRef', init_arg => undef);

has [qw(_segment_term _component_sep _repeat_sep _segment_term_suffix _element_sep)] => (is => 'bare', isa => 'Str', init_arg => undef);

has segment_counter => (is => 'rw', isa => 'Int', default => 0);

sub _parse {
    my ($self) = @_;

    if (substr($self->{buffer},0,3) eq 'ISA') {
        return if length($self->{buffer}) < 109; # ISA itself is 106 chars, but we need to see the beginning of GE to get the separator

        my $ISA = substr($self->{buffer},0,106,"");

        my $ver = substr($ISA, 84, 5);

        $self->{buffer} =~ s/^(\r?\n?)//;

        $self->set_delims(
            substr($ISA, 104, 1),
            ($ver ge '00402') ? substr($ISA, 82, 1) : undef,
            substr($ISA, 3, 1),
            substr($ISA, 105, 1),
            $1
        );

        # not quite a regular segment: values may include the component/repeat separator

        return [ map [[$_]], split /\Q$self->{_element_sep}/, substr($ISA,0,105) ];
    }

    unless ($self->{_segment_re}) {
        die "ISA segment must appear first\n";
    }

    # DIVERSITY: UNx, BIN, BDS segments, maybe X12.58 but I don't have a clear idea what that entails

    $self->{buffer} =~ s/$self->{_segment_re}// or return;
    my $segment = $1;

    # DIVERSITY: EDIFACT release characters

    my ($csep, $rsep, $esep) = @$self{qw( _component_sep _repeat_sep _element_sep )};

    return [
        map [
            map [ split /\Q$csep/, $_ ],
            (defined($rsep) ? split /\Q$rsep/, $_ : $_)
        ], split /\Q$esep/, $segment
    ];
}

sub set_delims {
    my $self = shift;

    @$self{ qw( _component_sep _repeat_sep _element_sep _segment_term _segment_term_suffix ) } = @_;

    my %u;
    if (grep( defined $_ && $u{$_}++, @$self{ qw( _element_sep _repeat_sep _component_sep _segment_term ) } )) {
        die "Delimiters are not unique\n";
    }

    my $t = $self->{_segment_term};
    my $ts = $self->{_segment_term_suffix};
    $self->{_segment_re} = "^([^\Q$t\E]*)\Q$t$ts\E";
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

sub get {
    my ($self) = @_;

    $self->peek;
    if ($self->{_lookahead}) {
        $self->{segment_counter}++;
        return delete $self->{_lookahead};
    }
    return undef;
}

sub peek_code {
    my ($self) = @_;

    $self->peek;

    return !$self->{_lookahead} ? '' : $self->{_lookahead}[0][0][0]; # DIVERSITY explicit nesting needs more info
}

sub expect_eof {
    my ($self) = @_;

    1 until length($self->{buffer}) or !$self->filler->();

    die "Unexpected data after transmission\n" if length($self->{buffer});
}

__PACKAGE__->meta->make_immutable;
