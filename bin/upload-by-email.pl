#!/usr/bin/env perl

=head1 NAME

upload-by-email.pl

=head1 SYNOPSIS

 $> ./upload-by-email.pl -c littleprinter.cfg < some-message.eml

=head1 DESCRIPTION

upload-by-email is a simple Perl script that parses an email containing a
photo attachment and sends it to Little Printer using the Direct Print API.

It can be run from the command line or (more likely) as an upload-by-email style
handler or callback that you'll need to configure yourself.

=head1 COMMAND LINE OPTIONS

=over 4

=item *

B<-c> is for "config"

The path to a config file containing your BERG Cloud direct print code and other
related information.

=back

=head1 CONFIG FILE

Config variables are defined in a plain vanilla '.ini' file.

 [littleprinter]
 direct_print_code=YOUR_DIRECT_PRINT_CODE
 root_fs=
 root_url=
 use_graphicsmagick=0

=head1 DEPENDENCIES

=over 4

=item

L<Email::MIME>

=item

L<Config::Simple>

=item

L<Image::Size>

=back

=head1 LICENSE

Copyright (c) 2013, Aaron Straup Cope. All Rights Reserved.

This is free software, you may use it and distribute it under the same terms as Perl itself.

=cut

use strict;
use warnings;

use Getopt::Std;
use Config::Simple;

use File::Spec;
use File::Basename;
use File::Temp;
use File::Copy;

use Email::MIME;
use Digest::MD5;
use Image::Size;
use HTML::Entities;   

use LWP::UserAgent;
use HTTP::Request;

{
    &main();
    exit;
}

sub main {

    my $txt = '';
    my %opts = ();

    getopts('c:', \%opts);

    if (! -f $opts{'c'}){
	warn "Not a valid config file";
	return 0;
    }
	
    my $cfg = Config::Simple->new($opts{'c'});

    while (<STDIN>){
	$txt .= $_;
    }

    my ($original_photo, $from) = parse_email($cfg, $txt);

    if (! $original_photo){
	return 0;
    }

    my $massaged_photo = massage_photo($cfg, $original_photo);

    if (! $massaged_photo){
	return 0;
    }

    my $html = generate_html($cfg, $massaged_photo, $from);

    my $ok = ($html) ? send_html($cfg, $html) : 0;

    unlink($original_photo);
    unlink($massaged_photo);

    print "send: $ok\n";
    return $ok;
}

sub parse_email {
    my $cfg = shift;
    my $txt = shift;

    my $email = Email::MIME->new($txt);
    my @parts = $email->parts;

    my $photo = undef;

    foreach my $p (@parts){

	my $type = $p->content_type;

	if ($type !~ m!image/jpeg!){
	    next;
	}

	my ($fh, $filename) = File::Temp::tempfile(SUFFIX => '.jpg');
	$photo = $filename;

	$fh->print($p->body);
	$fh->close();

	last;
    }

    if (! $photo){
	warn "Can't find photo";
	return undef;
    }

    my $from = $email->{'header'}->header('From');

    return ($photo, $from);
}

sub massage_photo {
    my $cfg = shift;
    my $original = shift;

    my $convert = "convert";

    if ($cfg->param('littleprinter.use_graphicsmagick')){
	$convert = "gm convert";
    }

    my $root = File::Basename::dirname($original);
    my $name = File::Basename::basename($original);

    $name = "lp-" . $name;

    my $tmp_file = File::Spec->catfile($root, $name);

    my ($w, $h) = imgsize($original);

    my @args = ();

    if ($w > $h){
	push @args, "-rotate 270"
    }

    push @args, "-geometry 384x -colorspace Gray";

    # TO DO: dithering...

    my $str_args = join(" ", @args);

    my $cmd = "$convert $str_args $original $tmp_file";

    if (system($cmd)){
	warn $!;
	return undef;
    }

    ($w, $h) = imgsize($tmp_file);

    if ($h > 800){
	my $cmd = "$convert -geometry x800 $tmp_file $tmp_file";

	if (system($cmd)){
	    warn $!;
	    return undef;
	}
    }

    my $md5sum = md5sum($tmp_file);

    my $m_root = File::Basename::dirname($tmp_file);
    my $m_fname = $md5sum . ".jpg";

    my $massaged = File::Spec->catfile($m_root, $m_fname);
    move($tmp_file, $massaged);

    return $massaged;
}

sub generate_html {
    my $cfg = shift;
    my $photo = shift;
    my $from = shift;

    my $root_fs = $cfg->param('littleprinter.root_filesystem');
    my $root_url = $cfg->param('littleprinter.root_url');

    my ($w, $h) = imgsize($photo);

    my $fname = File::Basename::basename($photo);
    my $path = File::Spec->catfile($root_fs, $fname);

    if (-f $path){
	warn "$path already exists, which means it's been sent already";
	return undef;
    }

    copy($photo, $path);

    my $url = $root_url . $fname;

    $from = encode_entities($from);

    my $html = '<img src="' . $url .'" height="' . $h . '" width="' . $w . '" class="dither" />';
    $html .= '<div style="margin-top:10px;font-family:sans-serif;">from <strong>' . $from . '</strong></div>';

    return $html;
}

sub send_html {
    my $cfg = shift;
    my $html = shift;

    my $code = $cfg->param('littleprinter.direct_print_code');
    my $url = "http://remote.bergcloud.com/playground/direct_print/$code";

    my $req = HTTP::Request->new("POST", $url);
    $req->content("html=$html");
    $req->content_type('application/x-www-form-urlencoded');

    my $ua = LWP::UserAgent->new();
    my $rsp = $ua->request($req);

    if ($rsp->code != 200){
	warn 'BERGCLOUD IS SAD: ' . $rsp->code . ', ' . $rsp->message;
	return 0;
    }

    return 1
}

sub md5sum {
    my $path = shift;
    
    my $fh = FileHandle->new();
    $fh->open($path);

    my $ctx = Digest::MD5->new();
    $ctx->addfile($fh);

    $fh->close();

    my $sum = $ctx->hexdigest();
    return $sum;
}

__END__

sub generate_html_b64 {
    my $photo = shift;

    my ($w, $h) = imgsize($photo);
    my $enc = encode_photo($photo);

    # This works:
    # my $html = '<img width="16" height="16" alt="star" src="data:image/gif;base64,R0lGODlhEAAQAMQAAORHHOVSKudfOulrSOp3WOyDZu6QdvCchPGolfO0o/XBs/fNwfjZ0frl3/zy7////wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACH5BAkAABAALAAAAAAQABAAAAVVICSOZGlCQAosJ6mu7fiyZeKqNKToQGDsM8hBADgUXoGAiqhSvp5QAnQKGIgUhwFUYLCVDFCrKUE1lBavAViFIDlTImbKC5Gm2hB0SlBCBMQiB0UjIQA7" />';

    # This doesn't:
    my $html = '<img src="data:image/jpg;base64,' . $enc . '" height="' . $h . '" width="' . $w . '" class="dither" />';

    return $html;
}

sub encode_photo {
    my $path = shift;

    local $/;

    my $fh = FileHandle->new();
    $fh->open($path);

    my $enc = MIME::Base64::encode_base64(<$fh>, '');

    $fh->close();
    return $enc;
}
