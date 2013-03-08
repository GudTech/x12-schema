package X12::Schema::SyntaxNote;

use Moose;
use namespace::autoclean;

has if_present   => (is => 'ro', isa => 'Str');
has then_require => (is => 'ro', isa => 'Str');

has all_or_none  => (is => 'ro', isa => 'ArrayRef[Str]');
has at_least_one => (is => 'ro', isa => 'ArrayRef[Str]');

has perl         => (is => 'ro', isa => 'CodeRef');

sub check {
    my ($self, $values) = @_;
    my $key;

    if ($key = $self->{if_present}) {
        if (defined($values->{$key}) && !defined($values->{$self->{then_require}})) {
            die "If $key is present, then so must be $self->{then_require}\n";
        }
    }
    elsif ($key = $self->{all_or_none}) {
        my $count = grep (defined $values->{$_}), @$key;
        if ($count && $count < @$key) {
            die "All or none of @$key must be present\n";
        }
    }
    elsif ($key = $self->{at_least_one}) {
        my $count = grep (defined $values->{$_}), @$key;
        if (!$count) {
            die "At least one of @$key must be present\n";
        }
    }
    elsif ($key = $self->{perl}) {
        $key->($values);
    }
}

sub BUILD {
    my ($self) = @_;

    if (1 != grep (defined $self->{$_}), qw( if_present all_or_none at_least_one perl )) {
        confess "syntax note must have exactly one type";
    }

    if ($self->{if_present} && !$self->{then_require}) {
        confess "if if_present is present, then then_require is required";
    }
}

__PACKAGE__->meta->make_immutable;
