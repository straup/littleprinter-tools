littleprinter-tools
==

Assorted tools for doing stuff with Little Printer.

upload-by-email.pl
--

upload-by-email is a simple Perl script that parses an email containing a photo
attachment and sends it to Little Printer using the Direct Print API. Photos are
resized and converted to greyscale (and rotated if they are wider than they are
tall) and written to a user-defined folder that can be reached on the
Interwebs.

This means you'll need to have a website. You'll need to have a website on the
same machine that the upload-by-email handler is on (and can write files
to). This is not ideal but test messages sent to the Direct Print API containing
even small images encoded as data blobs (rather than pointers to URLs) always
seem to make the BERG Cloud servers cry so this will have to do for now.

It can be run from the command line or (more likely) as an upload-by-email style
handler or callback that you'll need to configure yourself.

For example:

	$> ./upload-by-email.pl -c littleprinter.cfg < ~/test.eml

See also:

* [BERG Cloud Developers Direct Print Codes](http://remote.bergcloud.com/developers/direct_print_codes)
