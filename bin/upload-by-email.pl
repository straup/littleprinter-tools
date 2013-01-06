#!/usr/bin/env perl

=head1 NAME

upload-by-email.pl

=head1 SYNOPSIS

 $> ./upload-by-email.pl -c littleprinter.cfg < some-message.eml

=head1 DESCRIPTION

upload-by-email is a simple Perl script that parses an email containing a
photo attachment and sends it to Little Printer using the Direct Print API.

Photos are resized and converted to greyscale (and rotated if they are wider
than they are tall) and written to a user-defined folder that can be reached on
the Interwebs.

This means you'll need to have a website. You'll need to have a website on the
same machine that the upload-by-email handler is on (and can write files to).

This is not ideal but test messages sent to the Direct Print API containing even
small images encoded as data blobs always seem to make the BERG Cloud servers
cry so this will have to do for now.

It can be run from the command line or (more likely) as an upload-by-email style
handler or callback that you'll need to configure yourself.

=head1 ACCESS CONTROL

There is currently no access control for this tool. It is assumed that you will
create suitably "secret" email addresses for the people you trust to use it.

=head1 COMMAND LINE OPTIONS

=over 4

=item *

B<-c> is for "config"

The path to a config file containing your BERG Cloud direct print code and other
related information.

=item *

B<-l> is for "logfile" (optional)

The path to a log file where verbose status information will be written. Good
for debugging.

=back

=head1 CONFIG FILE

Config variables are defined in a plain vanilla '.ini' file.

 [littleprinter]
 direct_print_code=YOUR_DIRECT_PRINT_CODE
 root_fs=/path/to/example-dot-com/a-url-that-bergcloud-can-access/
 root_url=http://example.com/a-url-that-bergcloud-can-access/
 use_graphicsmagick=0

=head1 DEPENDENCIES

=over 4

=item

L<Email::MIME>

=item

L<Config::Simple>

=item

L<Log::Dispatch>

=item

L<Image::Size>

=item

L<ImageMagick> (or L<GraphicsMagick>)

=back

=head1 LICENSE

Copyright (c) 2013, Aaron Straup Cope. All Rights Reserved.

This is free software, you may use it and distribute it under the same terms as Perl itself.

=cut

use strict;
use warnings;

use Getopt::Std;
use Config::Simple;

use Log::Dispatch;
use Log::Dispatch::Screen;
use Log::Dispatch::FileRotate;

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

# mmmm.... globals

my $log;

{
    &main();
    exit;
}

sub main {

    $log = Log::Dispatch->new();

    $log->add(Log::Dispatch::Screen->new(
		  name      => 'screen',
		  min_level => 'info',
	      ));

    #

    my $txt = '';
    my %opts = ();

    getopts('c:l:', \%opts);

    if ($opts{'l'}){

	$log->add(Log::Dispatch::FileRotate->new(
		      name      => 'logfile',
		      min_level => 'debug',
		      filename  => $opts{'l'},
		      mode      => 'append' ,
		      size      => 1024 * 1024,
		      max       => 6,
		  ));
    }

    $log->debug("\n\ngetting started at " . time() . "\n-----------\n");

    if (! -f $opts{'c'}){
	$log->warning("Not a valid config file\n");
	return 0;
    }
	
    my $cfg = Config::Simple->new($opts{'c'});

    # TO DO: check max file size...

    while (<STDIN>){
	$txt .= $_;
    }

    my ($original_photo, $from, $subject) = parse_email($cfg, $txt);

    if (! $original_photo){
	return 0;
    }

    $log->info("parsed $original_photo from '$from': OK\n");

    my $massaged_photo = massage_photo($cfg, $original_photo);

    if (! $massaged_photo){
	return 0;
    }

    $log->info("massaged into $massaged_photo: OK\n");

    my $html = generate_html($cfg, $massaged_photo, $from, $subject);

    my $ok = ($html) ? send_html($cfg, $html) : 0;

    unlink($original_photo);
    unlink($massaged_photo);

    $log->info("send: $ok\n");
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
	$log->warning("Can't find photo\n");
	return undef;
    }

    my $from = $email->{'header'}->header('From');
    my $subject = $email->{'header'}->header('Subject');

    return ($photo, $from, $subject);
}

sub massage_photo {
    my $cfg = shift;
    my $original = shift;

    my $convert = "/usr/local/bin/convert";

    if ($cfg->param('littleprinter.use_graphicsmagick')){
	$convert = "gm convert";
    }

    my $root = File::Basename::dirname($original);
    my $name = File::Basename::basename($original);

    $name = "lp-" . $name;

    my $tmp_file = File::Spec->catfile($root, $name);

    # First, sort out the correct orientation

    my $cmd = "$convert -auto-orient $original $original";
    $log->debug("$cmd\n");

    if (system($cmd)){
	$log->warning("failed to convert image, $!\n");
	return undef;
    }

    # Now figure out if we're in portrait or landscape mode

    my ($w, $h) = imgsize($original);

    my @args = ();

    if ($w > $h){
	push @args, "-rotate 270";
    }

    if ($w > 384){
	push @args, "-geometry 384x";
    }

    push @args, "-colorspace Gray";

    # TO DO: dithering...

    my $str_args = join(" ", @args);

    my $cmd = "$convert $str_args $original $tmp_file";
    $log->debug("$cmd\n");

    if (system($cmd)){
	$log->warning("failed to convert image, $!\n");
	return undef;
    }

    ($w, $h) = imgsize($tmp_file);

    if ($h > 800){

	my $cmd = "$convert -geometry x800 $tmp_file $tmp_file";
	$log->debug("$cmd\n");

	if (system($cmd)){
	    $log->warning("failed to convert image, $!\n");
	    return undef;
	}
    }

    my $md5sum = md5sum($tmp_file);

    my $m_root = File::Basename::dirname($tmp_file);
    my $m_fname = $md5sum . ".jpg";

    my $massaged = File::Spec->catfile($m_root, $m_fname);

    $log->debug("tmp file: $tmp_file\n");
    $log->debug("massaged: $massaged\n");

    if (! move($tmp_file, $massaged)){
	$log->error("failed to move tmp file, $!\n");
	return undef;
    }

    return $massaged;
}

sub generate_html {
    my $cfg = shift;
    my $photo = shift;
    my $from = shift;
    my $subject = shift;

    my $root_fs = $cfg->param('littleprinter.root_fs');
    my $root_url = $cfg->param('littleprinter.root_url');

    my ($w, $h) = imgsize($photo);

    my $fname = File::Basename::basename($photo);
    my $path = File::Spec->catfile($root_fs, $fname);

    if (-f $path){
	$log->warning("$path already exists, which means it's been sent already\n");
	return undef;
    }

    $log->debug("copy massaged to $path\n");

    if (! copy($photo, $path)){
	$log->error("failed to copy massaged file, $!\n");
	return undef;
    }

    chmod 0644, $path;

    my $url = $root_url . $fname;

    $from = encode_entities($from);

    my $html = '<img src="' . $url .'" height="' . $h . '" width="' . $w . '" class="dither" />';
    $html .= '<br /><br />';

    if ($subject =~ /\w+/){
	$html .= "<q>$subject</q>, from ";
    }

    $html .= '<strong>' . $from . '</strong>';

    $log->debug($html . "\n");
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
	$log->warning('BERGCLOUD IS SAD: ' . $rsp->code . ', ' . $rsp->message . '\n');
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

# Would that we could just send the photo as a giant blob of base64 encoded text
# but it seems to be the sort of thing to make LP cry like a little baby...
# (20130106/straup)

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
