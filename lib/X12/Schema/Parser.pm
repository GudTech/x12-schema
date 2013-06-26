package X12::Schema::Parser;

use strict;
use warnings;
# not an instantiatable class

use X12::Schema::Element;
use X12::Schema::Constraint;
use X12::Schema::Segment;
use X12::Schema::SegmentUse;
use X12::Schema::Sequence;
use X12::Schema;

sub parse {
    my ($self, $filename, $text) = @_;

    my $root = $self->_extract_tree($filename, $text);
    return X12::Schema->new($self->_interpret_root($root));
}

sub _extract_tree {
    my ($self, $file, $text) = @_;

    # contains all items for which there is no less-or-equal-indented item further down
    my @open_items = ( { file => $file, line => 0, indent => -1, children => [] } );

    my $lineno = 0;
    for my $line (split /\n/, $text) {
        $lineno++;

        my ($indent, $body) = $line =~ /^([ \t]*+)([^#]*+)/;
        $body =~ s/\s*$//;

        die "$file:$lineno:Illegal hard tab\n" if $indent =~ /\t/;

        next unless $body;
        my $num_indent = length($indent);

        while ($num_indent <= $open_items[-1]{indent}) {
            pop @open_items;
        }

        # attach to nearest plausible ancestor, but enforce consistency

        my $sibling_indent = $open_items[-1]{children}[-1] ? $open_items[-1]{children}[-1]{indent} : undef;

        if (defined($sibling_indent) && $sibling_indent != $num_indent) {
            die "$file:$lineno:Inconsistent indentation; previous sibling indented $sibling_indent, this indented $num_indent\n";
        }

        my @toks = split ' ', $body;
        my $command = (@toks && $toks[0] =~ /:$/) ? shift(@toks) : '';
        my @flags;
        unshift @flags, pop @toks while @toks && $toks[-1] =~ /^\+/;

        my $new = { file => $file, line => $lineno, toks => \@toks, command => $command, flags => \@flags, indent => $num_indent, children => [] };
        push @{ $open_items[-1]{children} }, $new;
        push @open_items, $new;
    }

    return $open_items[0];
}

sub _error {
    my $node = shift;
    die join "", $node->{file}, ":", $node->{line}, ":", @_, "\n";
}

sub _noflags {
    my ($node,$thing) = @_;
    _error($node, ucfirst($thing)," does not accept flags") if @{ $node->{flags} };
}

sub _getflags {
    my ($node,$thing,@flags) = @_;

    my %fpassed;
    for my $fstr (@{ $node->{flags} }) {
        my $val = ($fstr =~ s/\((.*)\)$//) ? $1 : undef;
        if (exists $fpassed{$fstr}) { _error($node, "Duplicate flag $fstr") }
        $fpassed{$fstr} = $val;
    }

    my @out;
    my @fok;
    while (@flags) {
        my $fname = shift @flags;
        push @fok, $fname;

        my $ex  = exists $fpassed{$fname};
        my $val = delete $fpassed{$fname};
        if (ref $flags[0]) {
            my $re = shift @flags;
            if (!$ex) { push @out, undef; next }

            defined($val) or _error($node, "Flag $fname requires argument");
            $val =~ /$re/ or _error($node, "Flag $fname has invalid syntax");
            push @out, $val;
        } else {
            if (!$ex) { push @out, 0; next }
            defined($val) and _error($node, "Flag $fname does not use argument");
            push @out, 1;
        }
    }

    _error($node,"Invalid flag ",((sort keys %fpassed)[0])," for $thing, valid flags are: @fok") if %fpassed;

    return @out;
}

sub _interpret_root {
    my ($self, $node) = @_;

    my %pools = ( 'schema:' => [], 'segment:' => [], 'element:' => [] );

    for my $z (@{ $node->{children} }) {
        if ($pools{$z->{command}}) {
            push @{ $pools{$z->{command}} }, $z;
        } else {
            _error($z, "Root-level element in schema must be segment: or schema:");
        }
    }

    my %elements;

    for my $z (@{ $pools{'element:'} }) {
        my $el = $self->_interpret_element(undef, $z, 1);
        _error($z,"Duplicate definition of element ",$el->refno) if $elements{$el->refno};
        $elements{$el->refno} = $el;
    }

    my %segments;

    for my $z (@{ $pools{'segment:'} }) {
        my $seg = $self->_interpret_segment(\%elements, $z);
        _error($z,"Duplicate definition of segment ",$seg->tag) if $segments{$seg->tag};
        $segments{$seg->tag} = $seg;
    }

    _error($node, 'Missing schema: element') unless $pools{'schema:'}[0];
    _error($pools{'schema:'}[1], "Duplicate schema definition") if $pools{'schema:'}[1];

    return $self->_interpret_schema(\%segments, $pools{'schema:'}[0]);
}

sub _interpret_segment {
    my ($self, $elems, $node) = @_;

    my ($incomplete) = _getflags($node, "segment", "+incomplete");
    _error($node, "Segment syntax is segment: SHRT FriendlyName") unless @{ $node->{toks} } == 2;

    my ($short, $friendly) = @{ $node->{toks} };

    my @elements;
    my @constraints;
    my %elem_ok;

    for my $z (@{ $node->{children} }) {
        if ($z->{command} eq '') {
            push @elements, $self->_interpret_element($elems, $z, 0);
            $elem_ok{ $elements[-1]->name }++ and _error($z, "Duplicate hash key for segment element: ", $elements[-1]->name);
        }
        elsif ($z->{command} eq 'constraint:') {
            push @constraints, $z; # delay so that we can check element names
        }
        else {
            _error($z, "Child of a segment must be an element (unmarked) or a constraint:");
        }
    }

    @elements or $incomplete or _error($node, "Non-incomplete segment without defined elements");

    @constraints = map { $self->_interpret_constraint(\%elem_ok, $_) } @constraints;

    return X12::Schema::Segment->new(
        incomplete  => $incomplete,
        constraints => \@constraints,
        elements    => \@elements,
        tag         => $short,
        friendly    => $friendly,
    );
}

sub _interpret_constraint {
    my ($self, $elem_ok, $node) = @_;

    _noflags($node,"constraint");
    my $reparse = join " ", @{ $node->{toks} };

    my ($kind,$allelems) = $reparse =~ /^\s*(\w+)\s*\((\s*\w+\s*(?:,\s*\w+\s*)*)\)\s*$/
        or _error($node, "Constraint syntax is constraint: kind( A, B, C )");

    my @elems = split /,/, $allelems;
    map { s/^\s+|\s+$//g } @elems;

    @elems >= 2 or _error($node, "Constraint requires at least two elements");

    my %uniq;
    for my $e (@elems) {
        _error($node, "No such element $e") unless $elem_ok->{$e};
        _error($node, "Duplicate element $e") if $uniq{$e}++;
    }

    if ($kind eq 'all_or_none') {
        return X12::Schema::Constraint->new( all_or_none => \@elems );
    } elsif ($kind eq 'at_most_one') {
        return X12::Schema::Constraint->new( at_most_one => \@elems );
    } elsif ($kind eq 'at_least_one') {
        return X12::Schema::Constraint->new( at_least_one => \@elems );
    } elsif ($kind eq 'if_then_all') {
        return X12::Schema::Constraint->new( if_present => shift(@elems), require_all => \@elems );
    } elsif ($kind eq 'if_then_one') {
        return X12::Schema::Constraint->new( if_present => shift(@elems), require_one => \@elems );
    } else {
        _error($node, "Invalid constraint type $kind, must be one of (all_or_none, at_most_one, at_least_one, if_then_all, if_then_one)");
    }
}

sub _interpret_element {
    my ($self, $elems, $node, $free) = @_;

    my ($required, $raw, $refno) = _getflags($node, 'element', '+required', '+raw', '+element' => qr/^\d+$/);

    _error($node, "Reference number required in freestanding element definition") if $free && !$refno;

    if (!$free && $refno && @{ $node->{toks} } == 1) {
        my $tpl = $elems->{$refno} or _error($node, "Reference number $refno corresponds to no defined element");

        return X12::Schema::Element->new(
            required => $required, name => $node->{toks}[0], refno => $tpl->refno,
            type => $tpl->type, $tpl->expand ? (expand => $tpl->expand) : (),
        );
    }

    @{ $node->{toks} } == 3 or _error($node, "Element definition must be of the form FriendlyName TYPE MIN/MAX [+flags] or FriendlyName +element(REF)");
    my ($name, $type, $size) = @{ $node->{toks} };

    _error($node, "+required not valid when defining an element type") if $free && $required;

    my (%expand, %unexpand);

    _error($node, "+raw only permitted for ID") if $raw && $type ne 'ID';

    for my $z (@{ $node->{children} }) {
        _error($z, "Value definitions only permitted for ID-type elements without +raw") unless $type eq 'ID' && !$raw;
        _noflags($z, "value");
        my ($short, undef, $long) = @{ $z->{toks} };
        _error($z, "Value definition must be of the form SHORT -> LONG") unless $z->{command} eq '' && @{ $z->{toks} } == 3 && $z->{toks}[1] eq '->';
        _error($z, "Short value can contain only [0-9A-Z] chars") if $short =~ /[^0-9A-Z]/;
        _error($z, "Duplicate short value $short") if $expand{$short};
        _error($z, "Duplicate long value $long") if $unexpand{$long};
        $expand{$short} = $long;
        $unexpand{$long} = $short;
    }

    return X12::Schema::Element->new(
        required => $required,
        name => $name,
        type => "$type $size",
        ($refno  ? (refno => $refno) : ()),
        (%expand ? (expand => \%expand) : ()),
    );
}

sub _interpret_schema {
    my ($self, $elems, $node) = @_;
    my ($ignore_component_sep) = _getflags($node, 'schema', '+ignore_component_sep');
    return (
        root => $self->_interpret_loop_body('ROOT', 1, 1, $elems, $node),
        ignore_component_sep => $ignore_component_sep,
    );
}

sub _interpret_loop_body {
    my ($self, $name, $min, $max, $elems, $node) = @_;

    my @children;

    for my $z (@{ $node->{children} }) {
        if ($z->{command} eq 'loop:') {
            _noflags($z,"loop");
            (@{ $z->{toks} } == 2 && $z->{toks}[1] =~ /^(0|1)\/(N|\d+)$/) or _error($z, "Loop header must be of the form loop: HashKey [01]/ddd or HashKey [01]/N");
            push @children, $self->_interpret_loop_body($z->{toks}[0], $1, $2, $elems, $z);
        }
        elsif ($z->{command} eq '') {
            _noflags($z,"segment ref");
            @{ $z->{toks} } == 3 && $z->{toks}[2] =~ /^(0|1)\/(N|\d+)$/ or _error($z, "Segment ref must be of the form CODE HashKey MIN/MAX");
            my ($code, $name) = @{ $z->{toks} };
            $elems->{$code} or _error($z, "Code $code does not correspond to a defined segment");
            push @children, X12::Schema::SegmentUse->new(
                def => $elems->{$code},
                name => $name, required => ($1 eq '1' ? 1 : 0), max_use => ($2 eq 'N' ? undef : 0 + $2),
            );
        }
        else {
            _error($z, "Child of a loop: or schema: element must be a loop or segment reference");
        }
    }

    return X12::Schema::Sequence->new(
        children => \@children, required => $min eq '1', max_use => ($max eq 'N' ? undef : 0 + $max),
        name => $name,
    );
}

1;
