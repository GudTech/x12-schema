package X12::Schema::Constraint;

use Moose;
use namespace::autoclean;

has if_present   => (is => 'ro', isa => 'Str');
has require_all  => (is => 'ro', isa => 'ArrayRef[Str]');
has require_one  => (is => 'ro', isa => 'ArrayRef[Str]');

has all_or_none  => (is => 'ro', isa => 'ArrayRef[Str]');
has at_least_one => (is => 'ro', isa => 'ArrayRef[Str]');
has at_most_one  => (is => 'ro', isa => 'ArrayRef[Str]');

sub check {
    my ($self, $values) = @_;
    my $key;

    if ($key = $self->{if_present}) {
        my $test;
        if (defined($values->{$key})) {
            if ($test = $self->{require_one}) {
                return if grep defined($values->{$_}), @$test;
                return @$test;
            }
            elsif ($test = $self->{require_all}) {
                return grep !defined($values->{$_}), @$test;
            }
        }
    }
    elsif ($key = $self->{all_or_none}) {
        my $count = grep defined ($values->{$_}), @$key;
        if ($count && $count < @$key) {
            return grep !defined($values->{$_}), @$key;
        }
    }
    elsif ($key = $self->{at_least_one}) {
        my $count = grep defined ($values->{$_}), @$key;
        if (!$count) {
            return @$key;
        }
    }
    elsif ($key = $self->{at_most_one}) {
        my @present = grep defined ($values->{$_}), @$key;
        if (@present > 1) {
            return @present;
        }
    }
    return ();
}

sub describe {
    my ($self) = @_;
    my ($key, $test);

    if ($key = $self->{if_present}) {
        if ($test = $self->{require_one}) {
            return "If $key is present, then so must be one of @$test";
        }
        elsif ($test = $self->{require_all}) {
            return "If $key is present, then so must be all of @$test";
        }
    }
    elsif ($key = $self->{all_or_none}) {
        return "All or none of @$key must be present";
    }
    elsif ($key = $self->{at_least_one}) {
        return "At least one of @$key must be present";
    }
    elsif ($key = $self->{at_most_one}) {
        return "At most one of @$key must be present";
    }
}

sub BUILD {
    my ($self) = @_;

    if (1 != grep defined ($self->{$_}), qw( if_present all_or_none at_least_one at_most_one )) {
        confess "syntax note must have exactly one type";
    }

    if ($self->{if_present} && (1 != grep defined ($self->{$_}), qw( require_one require_all ))) {
        confess "if if_present is present, then then_require is required";
    }
}

__PACKAGE__->meta->make_immutable;
