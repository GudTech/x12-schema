package X12::Schema::Sequence;

use Moose;
use namespace::autoclean;
use Carp 'croak';

with 'X12::Schema::Sequencable';

has children => (isa => 'ArrayRef[X12::Schema::Sequencable]', is => 'ro', required => 1);
has hier_loop => (isa => 'Bool', is => 'ro');
has hier_unordered => (isa => 'Bool', is => 'ro');

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
            if ($elem->can('hier_loop') && $elem->hier_loop) {
                $passed = $elem->_unhier($passed);
            }

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

    for my $i ( reverse 0 .. $#$kids ) {
        $internal_cont[$i] = $self->{_cooked_empty}[$i] ?
            { %{ $self->{_cooked_begin}[$i] }, %{ $internal_cont[$i+1] } } :
            $self->{_cooked_begin}[$i];
    }

    for my $i ( 0 .. $#$kids ) {
        my $kid = $kids->[$i];

        printf "Looking for %s at %d (%s)\n", join('|', sort keys %{ $kid->_initial_tags }), $src->segment_counter+1, $src->peek_code
            if $src->trace > 0;
        if ($src->peek_code && !$internal_cont[$i]{$src->peek_code}) {
            my $p = $src->peek_code;
            $src->get;
            die "Unexpected segment $p at ".$src->segment_counter."\n";
        }

        if (defined($kid->max_use) && $kid->max_use == 1) {
            if ($kid->_initial_tags->{ $src->peek_code }) {
                $data{ $kid->name } = $kid->decode( $src, $internal_cont[$i+1] );
            } elsif ($kid->required) {
                die $kid->name." is required at ".($src->segment_counter+1)."\n";
            }
        }
        else {
            my @accum;
            while ($kid->_initial_tags->{ $src->peek_code }) {
                if (defined($kid->max_use) && @accum >= $kid->max_use) {
                    die $kid->name." exceeds ".$kid->max_use." occurrences at ".($src->segment_counter+1)."\n";
                }

                push @accum, $kid->decode( $src, { %{ $internal_cont[$i+1] }, %{ $self->{_cooked_begin}[$i] } } ); # may or may not loop back
            }

            if ($kid->required && !@accum) {
                die $kid->name." is required at ".($src->segment_counter+1)."\n";
            }

            if ($kid->can('hier_loop') && $kid->hier_loop) {
                $data{$kid->name} = $kid->_rehier(@accum);
            }
            else {
                $data{$kid->name} = \@accum;
            }
        }
    }

    return \%data;
}

sub _unhier {
    my ($self, $tree, $accum, $parentid) = @_;

    return [] unless defined($tree);

    if (ref($tree) ne 'HASH' || blessed($tree)) {
        die "Hierarchal loop ".$self->name." can only encode a HASH";
    }

    $accum ||= [];

    # ID ParentID LevelType HasChildren
    my %tmp = %$tree;
    my $id = delete($tmp{ID}) || (@$accum ? $accum->[-1]{HierLevel}{ID} + 1 : 1);
    my $leveltype = delete($tmp{LevelType}) || die "Hierarchal loop ".$self->name." requires LevelType";
    delete $tmp{ParentID}; delete $tmp{HasChildren};
    my $children = delete($tmp{Children}) || [];

    ref($children) eq 'ARRAY' && !blessed($children) or die "Hierarchal loop ".$self->name." requires ARRAY for children";
    $children = [grep { defined } @$children];

    $tmp{HierLevel} = { ID => $id, ParentID => $parentid, HasChildren => @$children ? 'Yes' : 'No', LevelType => $leveltype };
    push @$accum, \%tmp;
    $self->_unhier($_, $accum, $id) for @$children;
    return $accum;
}

sub _rehier {
    my ($self, @rows) = @_;

    my %nodes;
    my $root;
    my @stack;

    for my $n (@rows) {
        ref($n) eq 'HASH' && ref($n->{HierLevel}) eq 'HASH' && defined($n->{HierLevel}{ID}) && $n->{HierLevel}{LevelType} or die "Hierarchal loop ".$self->name.": data malformed, must have a single required HL segment";

        $n->{$_} = $n->{HierLevel}{$_} for qw( ID ParentID LevelType HasChildren );
        delete $n->{HierLevel};

        $nodes{$n->{ID}} and die "Hierarchal loop ".$self->name.": ID $n->{ID} repeated";
        $nodes{$n->{ID}} = $n;

        if (!defined($n->{ParentID})) {
            $root and die "Hierarchal loop ".$self->name.": two roots";
            $root = $n;
        }

        unless ($self->hier_unordered) {
            if (defined $n->{ParentID}) {
                while (@stack && $stack[-1]{ID} ne $n->{ParentID}) { pop @stack }
                @stack or die "Hierarchal loop ".$self->name.": node $n->{ID} is not properly in tree order";
            }
            push @stack, $n;
        }
    }

    for my $n (@rows) {
        if (defined $n->{ParentID}) {
            my $par = $nodes{$n->{ParentID}} or die "Hierarchal loop ".$self->name.": node $n->{ID} lacks parent";
            my $ptr = $par;
            while ($ptr) {
                $ptr == $n and die "Hierarchal loop ".$self->name.": node $n->{ID} participates in ancestry cycle";
                $ptr = defined($ptr->{ParentID}) ? $nodes{$ptr->{ParentID}} : undef;
            }
            push @{$par->{Children}}, $n;
        }
    }

    return $root; # may be undef
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
