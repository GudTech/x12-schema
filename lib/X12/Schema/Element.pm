package X12::Schema::Element;

use DateTime;

use Moose;
use namespace::autoclean;

has name       => (is => 'ro', isa => 'Str', required => 1);
has required   => (is => 'ro', isa => 'Bool', default => 0);

has type       => (is => 'ro', isa => 'Str', required => 1);
has expand     => (is => 'ro', isa => 'HashRef[Str]');

has scale      => (is => 'ro', isa => 'Int', init_arg => undef);
has min_length => (is => 'ro', isa => 'Int', init_arg => undef);
has max_length => (is => 'ro', isa => 'Int', init_arg => undef);
has contract   => (is => 'ro', isa => 'HashRef[Str]', init_arg => undef);

# DIVERSITY: composite data elements, element repetition

sub BUILD {
    my ($self) = @_;

    # DIVERSITY: EDIFACT uses different syntax
    $self->{type} =~ /^(N|AN|DT|TM|ID|R|B)(\d*) (\d+)\/(\d+)$/ or confess "type at BUILD must look like N5 10/20";

    confess "Numeric postfix used only with N" if $1 ne 'N' && $2; # N means N0
    confess "expand used only with type = ID" if ($1 ne 'ID') && (defined $self->expand);

    $self->{type} = $1;
    $self->{scale} = $2 || 0;
    $self->{min_length} = $3;
    $self->{max_length} = $4;

    $self->{contract} = $self->expand && { reverse %{ $self->expand } };
}

sub encode {
    my ($self, $sink, $value) = @_;

    my $type = $self->{type};
    my $method = "_encode_$type";

    my $string = $self->$method( $self->{min_length}, $self->{max_length}, $sink, $value );

    # DIVERSITY: use the release character when emitting UN/EDIFACT
    if ($type ne 'B' && $string =~ /$sink->{delim_re}/) {
        die "Value $string after encoding would contain a prohibited delimiter character from $sink->{delim_re} in ".$self->name."\n";
    }

    return $string;
}

# can't just use sprintf for these two because field widths are in _digits_.  sign magnitude hoy!
sub _encode_R {
    my ($self, $minp, $maxp, $sink, $value) = @_;
    my $string;
    my $prec = $maxp - 1;

    # DIVERSITY: exponential notation
    # this is a lot more complicated than it might otherwise be because the # of digits to the left of the decimal might increase after rounding on the right...

    while ($prec >= 0) {
        $string = sprintf "%.*f", $prec, $value;
        ($string =~ tr/0-9//) <= $maxp and !($prec && $string =~ /0$/) and last;
        $prec--;
    }

    if ($prec < 0) {
        die "Value $value cannot fit in $maxp digits for ".$self->name."\n";
    }

    my $wid = 0;

    while (1) {
        $string = sprintf "%0*.*f", $wid, $prec, $value;
        ($string =~ tr/0-9//) >= $minp and return $string;
        $wid++;
    }
}

sub _encode_N {
    my ($self, $minp, $maxp, $sink, $value) = @_;
    my $string;

    my $munge = sprintf "%.0f", $value * (10 ** $self->{scale});

    length(abs($munge)) > $maxp and die "Value $value cannot fit in $maxp digits for ".$self->name."\n";

    return sprintf "%0*d", ($munge < 0 ? $minp + 1 : $minp), $munge;
}

sub _encode_ID {
    my ($self, $minp, $maxp, $sink, $value) = @_;
    my $string;

    if ($self->contract) {
        $value = ($self->contract->{$value} || die "Value $value not contained in ".join(', ',sort keys %{$self->contract})." for ".$self->name."\n");
    }
    return $self->_encode_AN( $minp, $maxp, $sink, $value );
}

sub _encode_AN {
    my ($self, $minp, $maxp, $sink, $value) = @_;
    my $string;

    $string = "".$value;
    $string =~ s/ *$//;

    length($string) or die "Value $value must have at least one non-space for ".$self->name."\n";
    $string =~ /$sink->{non_charset_re}/ and die "Value $value contains a character outside the destination charset for ".$self->name."\n";
    $string =~ /\P{Print}/ and die "Value $value contains a non-printable character for ".$self->name."\n";

    length($string) > $maxp and die "Value $value does not fit in $maxp characters for ".$self->name."\n";
    length($string) < $minp and $string .= (" " x ($minp - length($string)));
    return $string;
}

    # on input, dates and times are not meaningfully associated (with each other, or with a time zone) so we have to generate isolated dates
    # (floating, 00:00 time) and isolated times (floating DateTime for 2000-01-01 - gross)
sub _encode_DT {
    my ($self, $minp, $maxp, $sink, $value) = @_;

    # send century if the field widths permit
    blessed($value) && $value->can('format_cldr') or die "Value $value is insufficiently date-like for ".$self->name."\n";
    $value->year > 0 && $value->year < 1e4 or die "Value $value is out of range for ".$self->name."\n";

    if (8 >= $minp && 8 <= $maxp) {
        return $value->format_cldr('yyyyMMdd');
    }
    elsif (6 >= $minp && 6 <= $maxp) {
        return $value->format_cldr('yyMMdd');
    }
    else {
        die "Field size does not permit any date format ".$self->name."\n";
    }
}

sub _encode_TM {
    my ($self, $minp, $maxp, $sink, $value) = @_;

    blessed($value) && $value->can('format_cldr') or die "Value $value is insufficiently date-like for ".$self->name."\n";

    if ($value->second >= 60) {
        # No leap seconds in X.12.  Round it
        $value = $value->clone->set_second(59);
    }

    # as much precision as permitted by the field.  TODO: maybe use a different input type that admits precision specs
    my $fmt = $maxp >= 6 ? 'HHmmss' . ('S' x ($maxp - 6)) : 'HHmm';
    length($fmt) >= $minp && length($fmt) <= $maxp or die "Field size does not permit any date format ".$self->name."\n";

    return $value->format_cldr($fmt);
}

sub _encode_B {
    my ($self, $minp, $maxp, $sink, $value) = @_;
    return $value;
}

__PACKAGE__->meta->make_immutable;
