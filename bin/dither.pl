#!/usr/bin/env perl

use strict;
use Imager;

use Data::Dumper;

{
    &main();
    exit;
}

sub main {

    my $infile = $ARGV[0];
    my $outfile = $ARGV[1];

    dither($infile, $outfile);
    return 1;
}

sub dither {
    my $infile = shift;
    my $outfile = shift;

    my @threshold = ();
    push @threshold, (0) x 128;
    push @threshold, (255) x 128;

    my $im = Imager->new();
    $im->read(file => $infile);

    $im = $im->convert(preset => 'gray');

    my $height = $im->getheight();
    my $width = $im->getwidth();

    for (my $y=0; $y < $height; $y++){

	for (my $x=0; $x < $width; $x++){

	    my $px = $im->getpixel(x => $x, y => $y, type => '8bit');
	    my @c = $px->rgba();

	    my $old = grayscale(@c);
	    my $new = $threshold[$old];

	    $im->setpixel(x => $x, y => $y, color => [ $new, $new, $new ]);

	    my $err = ($old - $new) >> 3;

	    # This does not work...

	    if (0){
	    foreach my $nxy ([$x+1, $y], [$x-1, $y+1], [$x, $y+1], [$x+1, $y+1], [$x, $y+2]){

		my $nx = $nxy->[0];
		my $ny = $nxy->[1];

		my $npx = $im->getpixel(x => $nx, y => $ny, type => '8bit');

		if (! $npx){
		    next;
		}

		my @nc = $npx->rgba();
		
		my $ngr = grayscale(@nc);
		$ngr += $err;

		$im->setpixel(x => $nx, y => $ny, color => [ $ngr, $ngr, $ngr ]);
	    }
	    }

	}
    }

    $im->write(file => $outfile);
}

sub grayscale {
    my ($r, $g, $b) = @_;

    # See also:
    # http://www.johndcook.com/blog/2009/08/24/algorithms-convert-color-grayscale/

    my $s = 0.15 * $r + 0.55 * $g + 0.30 * $b;
    return int($s);
}
