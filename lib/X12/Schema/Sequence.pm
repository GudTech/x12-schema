package X12::Schema::Sequence;

use Moose;
use namespace::autoclean;
use Carp 'croak';

with 'X12::Schema::Sequencable';

has children => (isa => 'ArrayRef[X12::Schema::Sequencable]', is => 'ro', required => 1);

has _cooked_begin    => (isa => 'ArrayRef[HashRef]', is => 'bare');
has _cooked_nofollow => (isa => 'ArrayRef[HashRef]', is => 'bare');
has _cooked_empty    => (isa => 'ArrayRef[Bool]', is => 'bare');

# DIVERSITY: These loop rules are much looser than prescribed by X12.6
# DIVERSITY: may need to handle UN/EDIFACT's explicit nesting indicators

sub encode {
    my ($self, $sink, $obj) = @_;

    die "Sequence ".$self->name." can only encode a HASH" unless $obj && ref($obj) eq 'HASH' && !blessed($obj);

    my %tmp = %$obj;  # we will remove things as they are processed
    my @output;

    for my $elem (@{ $self->children }) {
        my $passed = delete $tmp{ $elem->name };

        if (!defined($elem->max_use) || $elem->max_use > 1) {
            $passed ||= [];
            die "Replicated segment or loop ".$elem->name." must encode an ARRAY" unless ref($passed) eq 'ARRAY' && !blessed($passed);

            die "Segment or loop ".$elem->name." is required" if $elem->required && !@$passed;
            die "Segment or loop ".$elem->name." is limited to ".$elem->max_use." uses" if $elem->max_use && @$passed > $elem->max_use;

            $elem->encode($sink, $_) for @$passed;
        }
        else {
            die "Segment or loop ".$elem->name." is required" if $elem->required && !defined($passed);
            $elem->encode($sink, $passed) if defined($passed);
        }
    }

    die "Unused children passed to ".$self->name.": ".join(', ',sort keys %tmp) if %tmp;
}

sub decode {
    my ($self, $src, $exit_cont) = @_;

    my $kids = $self->{children};
    my @internal_cont;
    my %data;

    $internal_cont[ @$kids ] = $exit_cont;

    for my $i ( $#$kids .. 0 ) {
        $internal_cont[$i] = $self->{_cooked_empty}[$i] ?
            { %{ $self->{_cooked_begin}[$i] }, %{ $internal_cont[$i+1] } } :
            $self->{_cooked_begin}[$i];
    }

    for my $i ( 0 .. $#$kids ) {
        if ($src->peek_code && !$internal_cont[$i]{$src->peek_code}) {
            $src->get;
            die "Unexpected segment at ".$src->segment_counter."\n";
        }

        my $kid = $kids->[$i];

        if (defined($kid->max_use) && $kid->max_use == 1) {
            if ($kid->_initial_tags->{ $src->peek_code }) {
                $data{ $kid->name } = $kid->decode( $src, $internal_cont[$i+1] );
            } elsif ($kid->required) {
                die $kid->name." is required at ".$src->segment_counter."\n";
            }
        }
        else {
            my @accum;
            while ($kid->_initial_tags->{ $src->peek_code }) {
                if (defined($kid->max_use) && @accum >= $kid->max_use) {
                    die $kid->name." exceeds ".$kid->max_use." occurrences at ".$src->segment_counter."\n";
                }

                push @accum, $kid->decode( $src, $internal_cont[$i] ); # deliberately $i - we'll loop back
            }

            if ($kid->required && !@accum) {
                die $kid->name."is required at ".$src->segment_counter."\n";
            }

            $data{$kid->name} = \@accum;
        }
    }

    return \%data;
}

sub BUILD {
    my ($self) = @_;

    my $elems = $self->children;
    my (@begin, @nofollow, @empty);

    # Correct the values for min/max
    for my $child (@$elems) {
        push @begin,    $child->_initial_tags;
        push @nofollow, $child->_ambiguous_end_tags;
        push @empty,    $child->_can_be_empty;

        my $desc = "Child " . $child->name . " of " . $self->name;

        if (!defined($child->max_use) || $child->max_use > 1) {
            croak "$desc can be empty, so it may not be repeated unambiguously"
                if $empty[-1];
            croak "$desc is ambiguous when followed by itself"
                if grep { exists $nofollow[-1]{$_} } keys %{ $begin[-1] };

            $nofollow[-1] = { %{ $nofollow[-1] }, %{ $begin[-1] } };
        }

        if (!$child->required) {
            croak "$desc can already be empty, so it may not be optional" if $empty[-1];

            $nofollow[-1] = { %{ $nofollow[-1] }, %{ $begin[-1] } };
            $empty[-1] = 1;
        }
    }

    $self->{_cooked_empty} = \@empty;
    $self->{_cooked_nofollow} = \@nofollow;
    $self->{_cooked_begin} = \@begin;

    # get initial
    my %initial;
    my $can_be_empty = 1;
    for my $childix ( 0 .. $#$elems ) {
        %initial = (%initial, %{ $begin[$childix] });
        unless ($empty[$childix]) {
            $can_be_empty = 0;
            last;
        }
    }

    # check for composition errors
    my %excluded_from_continuation;

    for my $ix ( 0 .. $#$elems ) {
        my $herename = $elems->[$ix]->name;
        my ($conflict) = grep { exists $excluded_from_continuation{$_} } keys %{ $begin[$ix] };
        if ($conflict) {
            croak sprintf "In %s, %s can start with tag %s which makes the end of %s ambiguous",
                $self->name, $herename, $conflict, $excluded_from_continuation{$conflict};
        }

        %excluded_from_continuation = () unless $empty[$ix];
        for my $exclude (keys %{ $nofollow[$ix] }) {
            $excluded_from_continuation{$exclude} = $herename;
        }
    }

    $self->_can_be_empty($can_be_empty);
    $self->_ambiguous_end_tags(\%excluded_from_continuation);
    $self->_initial_tags(\%initial);
}

__PACKAGE__->meta->make_immutable;
