use strict;
use warnings;
use Test::More tests => 197;
use Test::Exception;

BEGIN { use_ok 'X12::Schema::Element'; }
use X12::Schema::TokenSink;
use X12::Schema::TokenSource;

my $sink = X12::Schema::TokenSink->new( element_sep => '*', segment_term => "~\n", component_sep => '\\', repeat_sep => '^', non_charset_re => qr/[^\x00-\xFF]/ );
my $src = X12::Schema::TokenSource->new( );

my $el;

throws_ok { X12::Schema::Element->new(name => 'Foo') } qr/type.*required/;
throws_ok { X12::Schema::Element->new(type => 'N 3/3') } qr/name.*required/;

throws_ok { X12::Schema::Element->new(name => 'Foo', type => 'X 2/3') } qr/type at BUILD must look like/;
throws_ok { X12::Schema::Element->new(name => 'Foo', type => 'R 2/3', expand => { }) } qr/expand/;
throws_ok { X12::Schema::Element->new(name => 'Foo', type => 'R3 2/3') } qr/Numeric postfix/;

sub elem_test {
    my $type = shift;
    my $expand = ($type =~ /^ID/) ? shift : undef;

    my ($el, $real);
    lives_ok { $el = X12::Schema::Element->new(name => 'EL', type => $type, $expand ? (expand => $expand) : ()) } "can parse $type" or return;

    while (@_) {
        my ($flag, $in, $out) = splice @_, 0, 3;
        my ($pin, $pout) = ($in, $out);
        s/[^ -~]//g for $pin, $pout;

        if ($flag eq 'encode') {
            if (ref($out)) {
                throws_ok { $el->encode($sink, $in) } qr/$out EL\n/, "encode fails ($type) ($pin) ($out)";
            } else {
                lives_ok { $real = $el->encode($sink, $in) } "encode succeeds ($type) ($pin)";
                is $real, $out, "result is ($pout)";
            }
        }
        elsif ($flag eq 'decode') {
            my ($err, $parsed) = $el->decode($src, $in);
            if ($out =~ /^elem/) {
                is $err, $out, "decode fails ($type) ($pin) ($pout)";
            } else {
                is_deeply $err, undef, "decode succeeds ($type) ($pin)";
                is_deeply $parsed, $out, "result is ($pout)";
            }
        }
    }
}

elem_test('R 1/5',
    encode => 0, '0',
    encode => 9, '9',
    encode => 9.5, '9.5',
    encode => 12.444, '12.444',
    encode => 12.4444, '12.444',
    encode => -12.444, '-12.444',
    encode => 0.25, '0.25',
    encode => 99999.2, '99999',
    encode => 99999.6, qr/Value 99999.6 cannot fit in 5 digits for/,
    encode => 9999.96, '10000',
    encode => -9999.96, '-10000',
    encode => -99999.6, qr/Value -99999.6 cannot fit in 5 digits for/,

    decode => '4', 4,
    decode => '4.', 4,
    decode => '4.2', 4.2,
    decode => '.4', .4,
    decode => '-.4', -.4,
    decode => '10E-1', 1,
    decode => '10E1', 100,
    decode => chr(0x663), 'elem_bad_syntax', # ARABIC-INDIC DIGIT THREE, matches \d (!)
    decode => '.', 'elem_bad_syntax',
    decode => '+4', 'elem_bad_syntax',
    decode => '1E+4', 'elem_bad_syntax',
);

elem_test('R 3/5',
    encode => 0, '000',
    encode => 95, '095',
    encode => 1.2, '01.2',
    encode => -1.2, '-01.2',
    encode => 3999, '3999',
    encode => -100000, qr/Value -100000 cannot fit in 5 digits for/,

    decode => '23', 'elem_too_short',
    decode => '-2.E-3', 'elem_too_short',
    decode => '230', 230,
    decode => '-230.0E-1', -23,
    decode => '123456', 'elem_too_long',
);

elem_test('N0 3/5',
    encode => 32.2, '032',
    encode => -995, '-995',
    encode => 99995, '99995',
    encode => -99995, '-99995',
    encode => 99999.9, qr/Value 99999.9 cannot fit in 5 digits for/,
    encode => -99999.9, qr/Value -99999.9 cannot fit in 5 digits for/,

    decode => '032', 32,
    decode => '-02', 'elem_too_short',
    decode => '123456', 'elem_too_long',
    decode => '-12345', -12345,
);

elem_test('N2 4/6',
    encode => 0, '0000',
    encode => -2, '-0200',
    encode => 0.02, '0002',

    decode => '-1234', -12.34,
);

elem_test('N 3/5',
    encode => 0, '000',
    encode => -2.4, '-002',
);

elem_test('ID 2/3', { A => 'SingleA', AA => 'DoubleA', AAA => 'TripleA' },
    encode => SingleA => 'A ',
    encode => DoubleA => 'AA',
    encode => TripleA => 'AAA',
    encode => TetraA => qr/Value TetraA not contained in DoubleA, SingleA, TripleA for/,
    encode => A => qr/Value A not contained in DoubleA, SingleA, TripleA for/,

    decode => 'A ' => 'SingleA',
    decode => AA => 'DoubleA',
    decode => AAA => 'TripleA',
    decode => 'AAA ' => 'elem_too_long',
    decode => AAAA => 'elem_bad_code',
    decode => "\n" => 'elem_bad_syntax',
    decode => A => 'elem_too_short',
    decode => ABC => 'elem_bad_code',
);

elem_test('ID 1/1', { 0 => 0 },
    encode => 0 => 0,
    decode => 0 => 0,
);

elem_test('AN 2/4',
    encode => 'F' => 'F ',
    encode => 'FF' => 'FF',
    encode => 'FFFF' => 'FFFF',
    encode => 'FFFFF' => qr/Value FFFFF does not fit in 4 characters for/,
    encode => 'F^' => qr/Value F\^ after encoding would contain a prohibited delimiter.*/,
    encode => 'F   ' =>  'F ',
    encode => ' F ' => ' F',
    encode => '   ' => qr/one non-space.*/,
    encode => "\r" => qr/non-print.*/,
    encode => "\x{3BB}" => qr/charset.*/,

    decode => "\r" => 'elem_bad_syntax',
    decode => 'F ' => 'F',
    decode => 'FFFF' => 'FFFF',
    decode => 'ABCD ' => 'elem_too_long',
    decode => 'X' => 'elem_too_short',
    decode => '   ' => 'elem_bad_syntax',
);

elem_test('DT 6/6',
    encode => DateTime->new(year => 1995, day => 23, month => 11), '951123',
    encode => DateTime->new(year => 2009, day =>  7, month =>  3), '090307',
    encode => DateTime->new(year => -1, day => 1, month => 1), qr/Value.*is out of range for/,

    decode => '19951123' => 'elem_too_long',
    # 2-digit year parse tests will start to fail in 2045
    decode => '951123' => DateTime->new(year => 1995, day => 23, month => 11),
    decode => '451123' => DateTime->new(year => 2045, day => 23, month => 11),
    decode => '45112' => 'elem_bad_syntax',
    decode => '4511234' => 'elem_bad_syntax',
    decode => '951323' => 'elem_bad_date',
    decode => '001131' => 'elem_bad_date',
);

elem_test('DT 6/8',
    encode => DateTime->new(year => 1995, day => 23, month => 11), '19951123',
    encode => DateTime->new(year => 2009, day =>  7, month =>  3), '20090307',
    encode => DateTime->new(year => -1, day => 1, month => 1), qr/Value.*is out of range for/,

    decode => '19951123' => DateTime->new(year => 1995, day => 23, month => 11),
);

elem_test('TM 4/4',
    encode => DateTime->new(year => 1970, hour =>  0, minute => 2, second => 3), '0002',
    encode => DateTime->new(year => 1970, hour => 11, minute => 2, second => 3), '1102',
    encode => DateTime->new(year => 1970, hour => 12, minute => 2, second => 3), '1202',
    encode => DateTime->new(year => 1970, hour => 23, minute => 2, second => 3), '2302',

    decode => '123456' => 'elem_too_long',
);

elem_test('TM 4/6',
    encode => DateTime->new(year => 1970, hour =>  0, minute => 2, second => 3), '000203',
    encode => DateTime->new(time_zone => 'UTC', year => 1972, month => 12, day => 31, hour => 23, minute => 59, second => 60), '235959',
);

elem_test('TM 4/8',
    encode => DateTime->new(year => 1970, hour =>  0, minute => 2, second => 3, nanosecond => 34e7), '00020334',

    decode => '00020334' => DateTime->new(year => 0, hour =>  0, minute => 2, second => 3, nanosecond => 34e7),
    decode => '00026034' => 'elem_bad_time',
    decode => '00600334' => 'elem_bad_time',
    decode => '24020334' => 'elem_bad_time',
);

elem_test('B 0/256',
    encode => join('',map chr, 0..255), join('',map chr, 0..255),
    decode => join('',map chr, 0..255), join('',map chr, 0..255),
);
