# Mail::Sender.pm version 0.7.13
#
# Copyright (c) 2001 Jan Krynicky <Jenda@Krynicky.cz>. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

package Mail::Sender; local $^W;
require 'Exporter.pm';
use vars qw(@ISA @EXPORT @EXPORT_OK);
@ISA = (Exporter);
@EXPORT = qw();
@EXPORT_OK = qw(@error_str GuessCType);

$Mail::Sender::VERSION='0.7.13';
$Mail::Sender::ver=$Mail::Sender::VERSION;

use strict 'vars';
use FileHandle;
use Socket;
use File::Basename;

use MIME::Base64;
use MIME::QuotedPrint;
                    # if you do not use MailFile or SendFile you may
                    # comment out these lines.
                    #MIME::Base64 and MIME::QuotedPrint may be found at CPAN.

# include config file :

#perl2exe_include Mail::Sender.config
BEGIN {
    my $config = $INC{'Mail/Sender.pm'};
    die "Wrong case in use statement or module renamed. Perl is case sensitive!!!\n" unless $config;
    $config =~ s/\.pm$/.config/;
    eval {require $config};
    if ($@ and $@ !~ /^Can't locate /) {
        print STDERR "Error in Mail::Sender.config : $@" ;
    }
}

#local IP address and name
my $local_name =  (gethostbyname 'localhost')[0];
my $local_IP =  join('.',unpack('CCCC',(gethostbyname $local_name)[4]));

#time diference to GMT
my $GMTdiff;
{
	my @local = (localtime())[3,2,1];
	my @gm = (gmtime())[3,2,1];
	if ($gm[0] > $local[0]) {$gm[1]+=24}
	my $hourdiff = $gm[1]-$local[1];
	my $mindiff;
	if (abs($gm[2]-$local[2])<5) {
		$mindiff = 0
	} elsif (abs($gm[2]-$local[2]-30) <5) {
		$mindiff = 30
	} elsif (abs($gm[2]-$local[2]-60) <5) {
		$mindiff = 0;
		$hourdiff ++;
	}
	$GMTdiff = ($hourdiff < 0 ? '+' : '-') . sprintf "%02d%02d", abs($hourdiff), $mindiff;
}

#data encoding
my $chunksize=1024*4;
my $chunksize64=71*57; # must be divisible by 57 !

sub enc_base64 {my $s = encode_base64($_[0]); $s =~ s/\x0A/\x0D\x0A/sg; return $s;}
my $enc_base64_chunk = 57;

sub enc_qp {my $s = encode_qp($_[0]); $s=~s/^\./../gm; $s =~ s/\x0A/\x0D\x0A/sg; return $s}

sub enc_plain {my $s = shift; $s=~s/^\./../gm; $s =~ s/(?:\x0D?\x0A|\x0D)/\x0D\x0A/sg; return $s}

#IO
use vars qw($debug);
$debug = 0;

#reads the whole SMTP response
# converts
#	nnn-very
#	nnn-long
#	nnn message
# to
#	nnn very
#	long
#	message
sub get_response {
	my $s = shift;
	my $res = <$s>;
	if ($res =~ s/^(\d\d\d)-/$1 /) {
		my $nextline = <$s>;
		while ($nextline =~ s/^\d\d\d-//) {
			$res .= $nextline;
			$nextline = <$s>;
		}
		$nextline =~ s/^\d\d\d //;
		$res .= $nextline;
	}
	$Mail::Sender::LastResponse = $res;
	return $res;
}

sub send_cmd {
	my ($s, $cmd) = @_;
	print $s "$cmd\x0D\x0A";
	get_response($s);
}

my $debug_code;
sub __Debug {
	my $self = shift();
	my $file = $self->{debug};
	if (defined $file) {
		unless (defined @Mail::Sender::DBIO::ISA) {
			eval "use Symbol;";
			eval $debug_code;
			die $@ if $@;
		}
		my $handle = gensym();
		if (! ref $file) {
			my $DEBUG = new FileHandle;
			open $DEBUG, ">$file" or die "Cannot open the debug file $file : $!\n";
			binmode $DEBUG;
			$DEBUG->autoflush();
			tie *$handle, 'Mail::Sender::DBIO', $self->{socket}, $DEBUG, 1;
		} else {
			my $DEBUG = $file;
			tie *$handle, 'Mail::Sender::DBIO', $self->{socket}, $DEBUG, 0;
		}
		$self->{socket} = $handle;
	}
}

#internale

sub HOSTNOTFOUND {
 $!=2;
 $Mail::Sender::Error="The SMTP server $_[0] was not found";
 return -1;
}

sub SOCKFAILED {
 $Mail::Sender::Error='socket() failed: $!';
 $!=5;
 return -2;
}

sub CONNFAILED {
 $Mail::Sender::Error="connect() failed: $!";
 $!=5;
 return -3;
}

sub SERVNOTAVAIL {
 $!=40;
 $Mail::Sender::Error="Service not available. Reply: $_[0]";
 return -4;
}

sub COMMERROR {
 $!=5;
 $Mail::Sender::Error="Server error: $_[0]";
 return -5;
}

sub USERUNKNOWN {
 $!=2;
 $Mail::Sender::Error="Local user \"$_[0]\" unknown on host \"$_[1]\"";
 return -6;
}

sub TRANSFAILED {
 $!=5;
 $Mail::Sender::Error="Transmission of message failed ($_[0])";
 return -7;
}

sub TOEMPTY {
 $!=14;
 $Mail::Sender::Error="Argument \$to empty";
 return -8;
}

sub NOMSG {
 $!=22;
 $Mail::Sender::Error="No message specified";
 return -9;
}

sub NOFILE {
 $!=22;
 $Mail::Sender::Error="No file name specified";
 return -10;
}

sub FILENOTFOUND {
 $!=2;
 $Mail::Sender::Error="File \"$_[0]\" not found";
 return -11;
}

sub NOTMULTIPART {
 $!=40;
 $Mail::Sender::Error="Not available in singlepart mode";
 return -12;
}

sub SITEERROR {
	$!=15;
	$Mail::Sender::Error="Site specific error";
	return -13;
}

sub NOTCONNECTED {
	$!=1;
	$Mail::Sender::Error="Connection not established. Didn't you mean MailFile instead of SendFile?";
	return -14;
}

sub NOSERVER {
	$!=22;
	$Mail::Sender::Error="No SMTP server specified";
	return -15;
}

sub NOFROMSPECIFIED {
 $!=22;
 $Mail::Sender::Error="No From: address specified";
 return -16;
}


@Mail::Sender::Errors = (
	'OK',
	'no From: address specified',
	'no SMTP server specified',
	'connection not established. Did you mean MailFile instead of SendFile?',
	'site specific error',
	'not available in singlepart mode',
	'file not found',
	'no file name specified in call to MailFile or SendFile',
	'no message specified in call to MailMsg or MailFile',
	'argument $to empty',
	'transmission of message failed',
	'local user $to unknown on host $smtp',
	'unspecified communication error',
	'service not available',
	'connect() failed',
	'socket() failed',
	'$smtphost unknown'
);

=head1 NAME

Mail::Sender - module for sending mails with attachments through an SMTP server

Version 0.7.13

=head1 SYNOPSIS

 use Mail::Sender;
 $sender = new Mail::Sender
  {smtp => 'mail.yourdomain.com', from => 'your@address.com'};
 $sender->MailFile({to => 'some@address.com',
  subject => 'Here is the file',
  msg => "I'm sending you the list you wanted.",
  file => 'filename.txt'});

=head1 DESCRIPTION

C<Mail::Sender> provides an object oriented interface to sending mails.
It doesn't need any outer program. It connects to a mail server
directly from Perl, using Socket.

Sends mails directly from Perl through a socket connection.

=head1 CONSTRUCTORS

=over 2

=item C<new Mail::Sender>

 new Mail::Sender ([from [,replyto [,to [,smtp [,subject [,headers [,boundary]]]]]]])
 new Mail::Sender {[from => 'somebody@somewhere.com'] , [to => 'else@nowhere.com'] [...]}

Prepares a sender. This doesn't start any connection to the server. You
have to use C<$Sender->Open> or C<$Sender->OpenMultipart> to start
talking to the server.

The parameters are used in subsequent calls to C<$Sender->Open> and
C<$Sender->OpenMultipart>. Each such call changes the saved variables.
You can set C<smtp>,C<from> and other options here and then use the info
in all messages.

 from      = the senders e-mail address

 fake_from = the address that will be shown in headers
             If not specified we use the value of "from"

 replyto   = the reply-to address

 to        = the recipient's address(es)

 fake_to   = the address that will be shown in headers
             If not specified we use the value of "to"

 cc        = address(es) to send a copy (carbon copy)

 fake_cc   = the address that will be shown in headers
             If not specified we use the value of "cc"

 bcc       = address(es) to send a copy (blind carbon copy)
             these addresses will not be visible in the mail!

 smtp      = the IP or domain address of your SMTP (mail) server
             This is the name of your LOCAL mail server, do not try to guess
             and contact directly the adressee's mailserver!

 subject   = the subject of the message

 headers   = the additional headers

 boundary  = the message boundary

 multipart = the MIME subtype for the whole message (Mixed/Related/Alternative)
  you may need to change this setting if you want to send a HTML body with some
  inline images, or if you want to post the message in plain text as well as
  HTML (alternative). See the examples at the end of the docs.
  You may also use the nickname "subtype".

 type      = the content type of a multipart message, may be usefull for
             multipart/related

 ctype     = the content type of a single part message

  Please do not confuse these two. The 'type' parameter is used to specify
  the overall content type of a multipart message (for example a HTML document
  with inlined images) while ctype is an ordinary content type for a single
  part message. For example a HTML mail message.

 encoding  = encoding of a single part message or the body of a multipart
  message. If the text of the message contains some extended characters or
  very long lines you should use 'encoding => "Quoted-printable"' in the
  call to Open(), OpenMultipart(), MailMsg() or MailFile().
  Keep in mind that if you use some encoding you should either use SendEnc()
  or encode the data yourself !

 charset   = the charset of the message

 client    = the name of the client computer. During the connection you send
  the mailserver your name. By default Mail::Sender sends
  (gethostbyname 'localhost')[0].
  If that is not the address you need, you can specify a different one.

 priority   = 1 = highest, 2 = high, 3 = normal
  "X-Priority: 1 (Highest)";

 debug      = "/path/to/debug/file.txt"
          or
            = \*FILEHANDLE
          or
            = $FH
			All the conversation with the server will be logged to that file or handle.
			All lines in the file should end with CRLF (the Windows and Internet format).
			If even a single one of them does not, please let me know!

 return codes:
  ref to a Mail::Sender object =  success
  -1 = $smtphost unknown
  -2 = socket() failed
  -3 = connect() failed
  -4 = service not available
  -5 = unspecified communication error
  -6 = local user $to unknown on host $smtp
  -7 = transmission of message failed
  -8 = argument $to empty
  -9 = no message specified in call to MailMsg or MailFile
  -10 = no file name specified in call to SendFile or MailFile
  -11 = file not found
  -12 = not available in singlepart mode
   $Mail::Sender::Error contains a textual description of last error.

=back

=cut
sub new {
 my $this = shift;
 my $class = ref($this) || $this;
 my $self = {};
 bless $self, $class;
 return $self->initialize(@_);
}

sub initialize {
 my $self = shift;

 delete $self->{buffer};
 $self->{debug} = 0;
 $self->{'proto'} = (getprotobyname('tcp'))[2];
 $self->{'port'} = getservbyname('smtp', 'tcp')||25 if not defined $self->{'port'};

 $self->{'boundary'} = 'Message-Boundary-19990614';
 $self->{'multipart'} = 'Mixed'; # default is Multipart/Mixed

 $self->{'client'} = $local_name;

 # Copy defaults from %Mail::Sender::default
 my $key;
 foreach $key (keys %Mail::Sender::default) {
  $self->{lc $key}=$Mail::Sender::default{$key};
 }

 if (@_ != 0) {
  if (ref $_[0] eq 'HASH') {
   my $hash=$_[0];
   $hash->{reply} = $hash->{replyto} if (defined $hash->{replyto} and !defined $hash->{reply});
   foreach $key (keys %$hash) {
    $self->{lc $key}=$hash->{$key};
   }
  } else {
   ($self->{'from'}, $self->{'reply'}, $self->{'to'}, $self->{'smtp'},
    $self->{'subject'}, $self->{'headers'}, $self->{'boundary'}
   ) = @_;
  }
 }

 $self->{'fromaddr'} = $self->{'from'};
 $self->{'replyaddr'} = $self->{'reply'};

 $self->{'to'} =~ s/\s+/ /g if (defined $self->{'to'}); # pack spaces and add comma
 $self->{'to'} =~ s/,,/,/g if (defined $self->{'to'});

 $self->{'cc'} =~ s/\s+/ /g if (defined $self->{'cc'}); # pack spaces and add comma
 $self->{'cc'} =~ s/,,/,/g if (defined $self->{'cc'});

 $self->{'bcc'} =~ s/\s+/ /g if (defined $self->{'bcc'}); # pack spaces and add comma
 $self->{'bcc'} =~ s/,,/,/g if (defined $self->{'bcc'});

 $self->{'fromaddr'} =~ s/.*<([^\s]*?)>/$1/ if ($self->{'fromaddr'}); # get from email address
 if ($self->{'replyaddr'}) {
  $self->{'replyaddr'} =~ s/.*<([^\s]*?)>/$1/; # get reply email address
  $self->{'replyaddr'} =~ s/^([^\s]+).*/$1/; # use first address
 }

 if (defined $self->{'smtp'}) {
  $self->{'smtp'} =~ s/^\s+//g; # remove spaces around $smtp
  $self->{'smtp'} =~ s/\s+$//g;

  $self->{'smtpaddr'} = inet_aton($self->{'smtp'});

  if (!defined($self->{'smtpaddr'})) { return $self->{'error'}=HOSTNOTFOUND($self->{smtp}); }
 }

 $self->{'boundary'} =~ tr/=/-/ if defined $self->{'boundary'};

 chomp $self->{'headers'} if defined $self->{'headers'};

 return $self;
}

sub Error {$_[0]->{'error'}};

sub GuessCType {
 local $_ = shift;
 /\.gif$/i and return 'image/gif';
 /\.jpe?g$/i and return 'image/jpeg';
 /\.s?html?$/i and return 'text/html';
 /\.txt$/i and return 'text/plain';
 /\.ini$/i and return 'text/plain';
 /\.doc$/i and return 'application/x-msword';
# /\.txt$/i and return 'text/plain';
 return 'application/octet-stream';
}

=head1 METHODS

=over 2

=item Open

 Open([from [, replyto [, to [, smtp [, subject [, headers]]]]]])
 Open({[from => "somebody@somewhere.com"] , [to => "else@nowhere.com"] [...]})

Opens a new message. If some parameters are unspecified or empty, it uses
the parameters passed to the "C<$Sender=new Mail::Sender(...)>";

See C<new Mail::Sender> for info about the parameters.

Returns ref to the Mail::Sender object if successfull, a negative error code if not.

=cut

sub Open {
 my $self = shift;
 local $_;
 if ($self->{'socket'}) {
  if ($self->{'error'}) {
   $self->Cancel;
  } else {
   $self->Close;
  }
 }
 delete $self->{'error'};
 delete $self->{'encoding'};
 my %changed;
 $self->{multipart}=0;

 if (ref $_[0] eq 'HASH') {
  my $key;
  my $hash=$_[0];
  $hash->{reply} = $hash->{replyto} if (defined $hash->{replyto} and !defined $hash->{reply});
  foreach $key (keys %$hash) {
   $self->{lc $key}=$hash->{$key};
   $changed{lc $key}=1;
  }
 } else {
  my ($from, $reply, $to, $smtp, $subject, $headers ) = @_;

  if ($from) {$self->{'from'}=$from;$changed{'from'}=1;}
  if ($reply) {$self->{'reply'}=$reply;$changed{'reply'}=1;}
  if ($to) {$self->{'to'}=$to;$changed{'to'}=1;}
  if ($smtp) {$self->{'smtp'}=$smtp;$changed{'smtp'}=1;}
  if ($subject) {$self->{'subject'}=$subject;$changed{'subject'}=1;}
  if ($headers) {$self->{'headers'}=$headers;$changed{'headers'}=1;}
 }

 $self->{'to'} =~ s/\s+/ /g if ($changed{to});
 $self->{'to'} =~ s/,,/,/g if ($changed{to});
 $self->{'cc'} =~ s/\s+/ /g if ($changed{cc});
 $self->{'cc'} =~ s/,,/,/g if ($changed{cc});
 $self->{'bcc'} =~ s/\s+/ /g if ($changed{bcc});
 $self->{'bcc'} =~ s/,,/,/g if ($changed{bcc});

 $self->{'boundary'} =~ tr/=/-/ if defined $changed{boundary};

 return $self->{'error'} = NOFROMSPECIFIED unless defined $self->{'from'};
 if ($changed{from}) {
  $self->{'fromaddr'} = $self->{'from'};
  $self->{'fromaddr'} =~ s/.*<([^\s]*?)>/$1/; # get from email address
 }

 if ($changed{reply}) {
  $self->{'replyaddr'} = $self->{'reply'};
  $self->{'replyaddr'} =~ s/.*<([^\s]*?)>/$1/; # get reply email address
  $self->{'replyaddr'} =~ s/^([^\s]+).*/$1/; # use first address
 }

 if ($changed{smtp}) {
  $self->{'smtp'} =~ s/^\s+//g; # remove spaces around $smtp
  $self->{'smtp'} =~ s/\s+$//g;
  $self->{'smtpaddr'} = inet_aton($self->{'smtp'});
 }

 chomp $self->{'headers'} if $changed{'headers'};

 if (!$self->{'to'}) { return $self->{'error'}=TOEMPTY; }

 return $self->{'error'}=NOSERVER() unless defined $self->{smtp};
 if (!defined($self->{'smtpaddr'})) { return $self->{'error'}=HOSTNOTFOUND($self->{smtp}); }

 if ($Mail::Sender::{SiteHook} and !$self->SiteHook()) {
  return defined $self->{'error'} ? $self->{'error'} : $self->{'error'}=&SITEERROR;
 }

 my $s = FileHandle->new();
 $self->{'socket'} = $s;

 if (!socket($s, AF_INET, SOCK_STREAM, $self->{'proto'})) {
   return $self->{'error'}=SOCKFAILED; }

 $self->{'smtpaddr'} = $1 if ($self->{'smtpaddr'} =~ /(.*)/); # Untaint

 $self->{'sin'} = sockaddr_in($self->{'port'}, $self->{'smtpaddr'});
 return $self->{'error'}=CONNFAILED unless connect($s, $self->{'sin'});

 binmode $s;
 my($oldfh) = select($s); $| = 1; select($oldfh);

 if ($self->{debug}) {
  $self->__Debug();
  $s = $self->{socket};
 }

 $_ = get_response($s); if (/^[45]/) { close $s; return $self->{'error'}=SERVNOTAVAIL($_); }

 $_ = send_cmd $s, "helo $self->{'client'}";
 if (/^[45]/) { close $s; return $self->{'error'}=COMMERROR($_); }

 $_ = send_cmd $s, "mail from: <$self->{'fromaddr'}>";
 if (/^[45]/) { close $s; return $self->{'error'}=COMMERROR($_); }

 { local $^W;
 foreach (split(/, */, $self->{'to'}),split(/, */, $self->{'cc'}),split(/, */, $self->{'bcc'})) {
  if (/<(.*)>/) {
   $_ = send_cmd $s, "rcpt to: <$1>";
  } else {
   $_ = send_cmd $s, "rcpt to: <$_>";
  }
  if (/^[45]/) { close $s; return $self->{'error'}=USERUNKNOWN($self->{to}, $self->{smtp}); }
 }
 }

 $_ = send_cmd $s, "data";
 if (/^[45]/) { close $s; return $self->{'error'}=COMMERROR($_); }

 $self->{'ctype'} = 'text/plain' if (defined $self->{'charset'} and !defined $self->{'ctype'});

 my $headers;
 if (defined $self->{'encoding'} or defined $self->{'ctype'}) {
  $headers = 'MIME-Version: 1.0';
  $headers .= "\r\nContent-type: $self->{'ctype'}" if defined $self->{'ctype'};
  $headers .= "; charset=$self->{'charset'}" if defined $self->{'charset'};

  undef $self->{'chunk_size'};
  if (defined $self->{'encoding'}) {
   $headers .= "\r\nContent-transfer-encoding: $self->{'encoding'}";
   if ($self->{'encoding'} =~ /Base64/i) {
    $self->{'code'}=\&enc_base64;
    $self->{'chunk_size'} = $enc_base64_chunk;
   } elsif ($self->{'encoding'} =~ /Quoted[_\-]print/i) {
    $self->{'code'}=\&enc_qp;
   }
  }
 }
 $self->{'code'}=\&enc_plain unless $self->{code};

 print $s "To: ", defined $self->{'fake_to'} ? $self->{'fake_to'} : $self->{'to'},"\r\n";
 print $s "From: ", defined $self->{'fake_from'} ? $self->{'fake_from'} : $self->{'from'},"\r\n";
 if (defined $self->{'fake_cc'}) {
  print $s "Cc: $self->{'fake_cc'}\r\n";
 } elsif (defined $self->{'cc'}) {
  print $s "Cc: $self->{'cc'}\r\n";
 }
 print $s "Reply-to: $self->{'reply'}\r\n" if defined $self->{'reply'};
 print $s qq{X-Mailer: Perl script "$0" using Mail::Sender $Mail::Sender::ver by Jenda Krynicky\r\n\trunning on $local_name ($local_IP)\r\n}
	unless defined $Mail::Sender::NO_X_MAILER;
 {
  my $date = localtime(); $date =~ s/^(\w+)\s+(\w+)\s+(\d+)\s+(\d+:\d+:\d+)\s+(\d+)$/$1, $3 $2 $5 $4/;
  print $s "Date: $date $GMTdiff\r\n" unless defined $Mail::Sender::NO_DATE;
 }
 print $s "Message-ID: ".MessageID($self->{'fromaddr'})."\r\n"
	 unless defined $Mail::Sender::NO_MESSAGE_ID;
 if (defined $Mail::Sender::SITE_HEADERS) { print $s $Mail::Sender::SITE_HEADERS,"\r\n" };
 print $s $self->{'headers'},"\r\n" if defined $self->{'headers'} and $self->{'headers'};
 print $s $headers,"\r\n" if defined $headers;
 $self->{'subject'} = "<No subject>" unless defined $self->{'subject'};
 print $s "Subject: $self->{'subject'}\r\n\r\n";

 return $self;
}

=item OpenMultipart

 OpenMultipart([from [, replyto [, to [, smtp [, subject [, headers [, boundary]]]]]]])
 OpenMultipart({[from => "somebody@somewhere.com"] , [to => "else@nowhere.com"] [...]})

Opens a multipart message. If some parameters are unspecified or empty, it uses
the parameters passed to the C<$Sender=new Mail::Sender(...)>.

See C<new Mail::Sender> for info about the parameters.

Returns ref to the Mail::Sender object if successfull, a negative error code if not.

=cut

sub OpenMultipart {
 my $self = shift;
 local $_;
 if ($self->{'socket'}) {
  if ($self->{'error'}) {
   $self->Cancel;
  } else {
   $self->Close;
  }
 }
 delete $self->{'error'};
 delete $self->{'encoding'};
 my %changed;
 $self->{'multipart'}='Mixed' unless $self->{'multipart'};
 $self->{'idcounter'} = 0;

 if (ref $_[0] eq 'HASH') {
  my $key;
  my $hash=$_[0];
  $hash->{'multipart'} = $hash->{subtype} if defined $hash->{subtype};
  $hash->{reply} = $hash->{replyto} if (defined $hash->{replyto} and !defined $hash->{reply});
  foreach $key (keys %$hash) {
   $self->{lc $key}=$hash->{$key};
   $changed{lc $key}=1;
  }
 } else {
  my ($from, $reply, $to, $smtp, $subject, $headers, $boundary) = @_;

  if ($from) {$self->{'from'}=$from;$changed{'from'}=1;}
  if ($reply) {$self->{'reply'}=$reply;$changed{'reply'}=1;}
  if ($to) {$self->{'to'}=$to;$changed{'to'}=1;}
  if ($smtp) {$self->{'smtp'}=$smtp;$changed{'smtp'}=1;}
  if ($subject) {$self->{'subject'}=$subject;$changed{'subject'}=1;}
  if ($headers) {$self->{'headers'}=$headers;$changed{'headers'}=1;}
  if ($boundary) {
   $self->{'boundary'}=$boundary;
  }
 }

 $self->{'to'} =~ s/\s+/ /g if ($changed{to});
 $self->{'to'} =~ s/,,/,/g if ($changed{to});
 $self->{'cc'} =~ s/\s+/ /g if ($changed{cc});
 $self->{'cc'} =~ s/,,/,/g if ($changed{cc});
 $self->{'bcc'} =~ s/\s+/ /g if ($changed{bcc});
 $self->{'bcc'} =~ s/,,/,/g if ($changed{bcc});
 $self->{'boundary'} =~ tr/=/-/ if $changed{boundary};
 chomp $self->{'headers'} if $changed{'headers'};

 return $self->{'error'} = NOFROMSPECIFIED unless defined $self->{'from'};
 if ($changed{from}) {
  $self->{'fromaddr'} = $self->{'from'};
  $self->{'fromaddr'} =~ s/.*<([^\s]*?)>/$1/; # get from email address
 }

 if ($changed{reply}) {
  $self->{'replyaddr'} = $self->{'reply'};
  $self->{'replyaddr'} =~ s/.*<([^\s]*?)>/$1/; # get reply email address
  $self->{'replyaddr'} =~ s/^([^\s]+).*/$1/; # use first address
 }

 if ($changed{smtp}) {
  $self->{'smtp'} =~ s/^\s+//g; # remove spaces around $smtp
  $self->{'smtp'} =~ s/\s+$//g;
  $self->{'smtpaddr'} = inet_aton($self->{'smtp'});
 }

 if (!$self->{'to'}) { return $self->{'error'}=TOEMPTY; }

 return $self->{'error'}=NOSERVER() unless defined $self->{smtp};
 if (!defined($self->{'smtpaddr'})) { return $self->{'error'}=HOSTNOTFOUND($self->{smtp}); }

 if ($Mail::Sender::{SiteHook} and !$self->SiteHook()) {
  return defined $self->{'error'} ? $self->{'error'} : $self->{'error'}=&SITEERROR;
 }

 my $s = FileHandle->new();
 $self->{'socket'} = $s;

 if (!socket($s, AF_INET, SOCK_STREAM, $self->{'proto'})) {
   return $self->{'error'}=SOCKFAILED; }

 $self->{'smtpaddr'} = $1 if ($self->{'smtpaddr'} =~ /(.*)/); # Untaint

 $self->{'sin'} = sockaddr_in($self->{'port'}, $self->{'smtpaddr'});
 return $self->{'error'}=CONNFAILED unless connect($s, $self->{'sin'});

 binmode $s;
 my($oldfh) = select($s); $| = 1; select($oldfh);

 if ($self->{debug}) {
  $self->__Debug();
  $s = $self->{socket};
 }

 $_ = get_response($s); if (/^[45]/) { close $s; return $self->{'error'}=SERVNOTAVAIL($_); }

 $_ = send_cmd $s, "helo $self->{'client'}";
 if (/^[45]/) { close $s; return $self->{'error'}=COMMERROR($_); }

 $_ = send_cmd $s, "mail from: <$self->{'fromaddr'}>";
 if (/^[45]/) { close $s; return $self->{'error'}=COMMERROR($_); }

 {
  my $list = $self->{'to'};	#assumed to be always present
  $list .= ",$self->{'cc'}"  if defined $self->{'cc'};
  $list .= ",$self->{'bcc'}" if defined $self->{'bcc'};
  foreach (split(/, */, $list)) {
   if (/<(.*)>/) {
    $_ = send_cmd $s, "rcpt to: <$1>";
   } else {
    $_ = send_cmd $s, "rcpt to: <$_>";
   }
   if (/^[45]/) { close $s; return $self->{'error'}=USERUNKNOWN($self->{to}, $self->{smtp}); }
  }
 }

 $_ = send_cmd $s, "data";
 if (/^[45]/) { close $s; return $self->{'error'}=COMMERROR($_); }

 print $s "To: ", defined $self->{'fake_to'} ? $self->{'fake_to'} : $self->{'to'},"\r\n";
 print $s "From: ", defined $self->{'fake_from'} ? $self->{'fake_from'} : $self->{'from'},"\r\n";
 if (defined $self->{'fake_cc'}) {
  print $s "Cc: $self->{'fake_cc'}\r\n";
 } elsif (defined $self->{'cc'}) {
  print $s "Cc: $self->{'cc'}\r\n";
 }
 print $s "Reply-to: $self->{'reply'}\r\n" if $self->{'reply'};
 print $s qq{X-Mailer: Perl script "$0" using Mail::Sender $Mail::Sender::ver by Jenda Krynicky\r\n\trunning on $local_name ($local_IP)\r\n}
	unless defined $Mail::Sender::NO_X_MAILER;
 if (defined $Mail::Sender::SITE_HEADERS) {print $s $Mail::Sender::SITE_HEADERS,"\r\n"};
 {
  my $date = localtime(); $date =~ s/^(\w+)\s+(\w+)\s+(\d+)\s+(\d+:\d+:\d+)\s+(\d+)$/$1, $3 $2 $5 $4/;
  print $s "Date: $date $GMTdiff\r\n" unless defined $Mail::Sender::NO_DATE;
 }
 print $s "Message-ID: ".MessageID($self->{'fromaddr'})."\r\n"
	 unless defined $Mail::Sender::NO_MESSAGE_ID;
 $self->{'subject'} = "<No subject>" unless defined $self->{'subject'};
 print $s "Subject: $self->{'subject'}\r\n";
 print $s $self->{'headers'},"\r\n" if defined $self->{'headers'} and $self->{'headers'};
 print $s "MIME-Version: 1.0\r\nContent-type: Multipart/$self->{'multipart'};\r\n\tboundary=\"$self->{'boundary'}\"";
 print $s ";\r\n\ttype=$self->{'type'}" if defined $self->{'type'};
 print $s "\r\n\r\n";

 return $self;
}


=item MailMsg

 MailMsg([from [, replyto [, to [, smtp [, subject [, headers]]]]]], message)
 MailMsg({[from => "somebody@somewhere.com"]
          [, to => "else@nowhere.com"] [...], msg => "Message"})

Sends a message. If a mail in $sender is opened it gets closed
and a new mail is created and sent. $sender is then closed.
If some parameters are unspecified or empty, it uses
the parameters passed to the "C<$Sender=new Mail::Sender(...)>";

See C<new Mail::Sender> for info about the parameters.

The module was made so that you could create an object initialized with
all the necesary options and then send several messages without need to
specify the SMTP server and others each time. If you need to send only
one mail using MailMsg() or MailFile() you do not have to create a named
object and then call the method. You may do it like this :

 (new Mail::Sender)->MailMsg({smtp => 'mail.company.com', ...});

Returns ref to the Mail::Sender object if successfull, a negative error code if not.

=cut

sub MailMsg {
 my $self = shift;
 my $msg;
 local $_;
 if (ref $_[0] eq 'HASH') {
  my $hash=$_[0];
  $msg=$hash->{msg};
  delete $hash->{msg}
 } else {
  $msg = pop;
 }
 return $self->{'error'}=NOMSG unless $msg;

 ref $self->Open(@_)
 and
 $self->SendEnc($msg)
 and
 $self->Close >= 0
 and
 return $self;
}


=item MailFile

 MailFile([from [, replyto [, to [, smtp [, subject [, headers]]]]]], message, file(s))
 MailFile({[from => "somebody@somewhere.com"]
           [, to => "else@nowhere.com"] [...],
           msg => "Message", file => "File"})

Sends one or more files by mail. If a mail in $sender is opened it gets closed
and a new mail is created and sent. $sender is then closed.
If some parameters are unspecified or empty, it uses
the parameters passed to the "C<$Sender=new Mail::Sender(...)>";

The C<file> parameter may be a "filename", a "list, of, file, names" or a \@list of file names.

see C<new Mail::Sender> for info about the parameters.

Just keep in mind that parameters like ctype, charset and encoding
will be used for the attached file, not the body of the message.
If you want to specify those parameters for the body you have to use
b_ctype, b_charset and b_encoding. Sorry.

Returns ref to the Mail::Sender object if successfull, a negative error code if not.

=cut

sub MailFile {
 my $self = shift;
 my $msg;
 local $_;
 my ($file, $desc, $haddesc,$ctype,$charset,$encoding);
 my @files;
 if (ref $_[0] eq 'HASH') {
  my $hash = $_[0];
  $msg = $hash->{msg};
  delete $hash->{msg};

  $file=$hash->{file};
  delete $hash->{file};

  $desc=$hash->{description}; $haddesc = 1 if defined $desc;
  delete $hash->{description};

  $ctype=$hash->{ctype};
  delete $hash->{ctype};

  $charset=$hash->{charset};
  delete $hash->{charset};

  $encoding=$hash->{encoding};
  delete $hash->{encoding};

 } else {
  $desc=pop if ($#_ >=2); $haddesc = 1 if defined $desc;
  $file = pop;
  $msg = pop;
 }
 return $self->{'error'}=NOMSG unless $msg;
 return $self->{'error'}=NOFILE unless $file;

 if (ref $file eq 'ARRAY') {
  @files=@$file;
 } elsif ($file =~ /,/) {
  @files=split / *, */,$file;
 } else {
  @files = ($file);
 }
 foreach $file (@files) {
  return $self->{'error'}=FILENOTFOUND($file) unless ($file =~ /^&/ or -e $file);
 }

 ref $self->OpenMultipart(@_)
 and
 ref $self->Body(
      $self->{'b_charset'},
      $self->{'b_encoding'},
      $self->{'b_ctype'}
     )
 and
 $self->SendEnc($msg)
 or return undef;
 $Mail::Sender::Error = '';
 foreach $file (@files) {
  my $cnt;
  my $filename = basename $file;
  my $ctype = $ctype || GuessCType $filename;
  my $encoding = $encoding || ($ctype =~ m#^text/#i ? 'Quoted-printable' : 'BASE64');

  $desc = $filename unless (defined $haddesc);

  $self->Part({encoding => $encoding,
               disposition => $self->{'disposition'},  #"attachment; filename=\"$filename\"",
               ctype => "$ctype; name=\"$filename\"; type=Unknown;" . (defined $charset ? "charset=$charset;" : ''),
               description => $desc});

  my $code = $self->{'code'};

  my $FH = new FileHandle;
  if (!open $FH, "<$file") {
	$Mail::Sender::Error .= "File \"$file\" not found\n";
	next;
  }
  binmode $FH unless $ctype =~ m#^text/#i and $encoding =~ /Quoted[_\-]print|Base64/i;
  my $s;
  $s = $self->{'socket'};
  my $mychunksize = $chunksize;
  $mychunksize = $chunksize64 if defined $self->{chunk_size};
  while (read $FH, $cnt, $mychunksize) {
   print $s (&$code($cnt));
  }
  close $FH;
 }
 if ($Mail::Sender::Error eq '') {
	undef $Mail::Sender::Error;
 } else {
	chomp $Mail::Sender::Error;
 }
 $self->Close;
 return $self;
}



=item Send

 Send(@strings)

Prints the strings to the socket. Doesn't add any end-of-line characters.
Doesn't encode the data! You should use C<\r\n> as the end-of-line!

UNLESS YOU ARE ABSOLUTELY SURE YOU KNOW WHAT YOU ARE DOING
YOU SHOULD USE SendEnc() INSTEAD!

Returns 1 if successfull.

=cut
sub Send {
 my $self = shift;
 my $s;
 $s = $self->{'socket'};
 print $s @_;
 return 1;
}

=item SendLine

 SendLine(@strings)

Prints the strings to the socket. Adds the end-of-line character at the end.
Doesn't encode the data! You should use C<\r\n> as the end-of-line!

UNLESS YOU ARE ABSOLUTELY SURE YOU KNOW WHAT YOU ARE DOING
YOU SHOULD USE SendEnc() INSTEAD!

Returns 1 if successfull.

=cut

sub SendLine {
 my $self = shift;
 my $s;
 $s = $self->{'socket'};
 print $s (@_,"\r\n");
 return 1;
}

=item print

Alias to SendEnc().

Keep in mind that you can't write :

	print $sender "...";

you have to use

	$sender->print("...");

If you want to be able to print into the message as if it was a normal file handle take a look at C<GetHandle>()

=item SendEnc

 SendEnc(@strings)

Prints the strings to the socket. Doesn't add any end-of-line characters.

Encodes the text using the selected encoding (none/Base64/Quoted-printable)

Returns 1 if successfull.

=cut

sub SendEnc {
 my $self = shift;
 local $_;
 my $code = $self->{code};
# return $self->Send(@_) unless defined $code;
 $self->{code}= $code = \&enc_plain
		unless defined $code;
 my $s;
 $s = $self->{'socket'};
 if (defined $self->{'chunk_size'}) {
  my $str;
  my $chunk = $self->{'chunk_size'};
  if (defined $self->{buffer}) {
   $str=(join '',($self->{buffer},@_));
  } else {
   $str=join '',@_;
  }
  my ($len,$blen);
  $len = length $str;
  if (($blen=($len % $chunk)) >0) {
   $self->{buffer} = substr($str,($len-$blen));
   print $s (&$code(substr( $str,0,$len-$blen)));
  } else {
   delete $self->{buffer};
   print $s (&$code($str));
  }
 } else {
  print $s (&$code(join('',@_)));
 }
 return 1;
}

sub print;*print = \&SendEnc;

=item SendLineEnc

 SendLineEnc(@strings)

Prints the strings to the socket. Add the end-of-line character at the end.
Encodes the text using the selected encoding (none/Base64/Quoted-printable).

Do NOT mix up /Send(Line)?(Ex)?/ and /Send(Line)?Enc/! SendEnc does some buffering
necessary for correct Base64 encoding, and /Send(Ex)?/ is not aware of that!

Usage of /Send(Line)?(Ex)?/ in non 7BIT parts not recommended.
Using C<Send(encode_base64($string))> may work, but more likely it will not!
In particular if you use several such to create one part,
the data is very likely to get crippled.

Returns 1 if successfull.

=cut

sub SendLineEnc {
 push @_, "\r\n";
 goto &SendEnc;
}

=item SendEx

 SendEx(@strings)

Prints the strings to the socket. Doesn't add any end-of-line characters.
Changes all end-of-lines to C<\r\n>. Doesn't encode the data!

UNLESS YOU ARE ABSOLUTELY SURE YOU KNOW WHAT YOU ARE DOING
YOU SHOULD USE SendEnc() INSTEAD!

Returns 1 if successfull.

=cut

sub SendEx {
 my $self = shift;
 my $s;
 $s = $self->{'socket'};
 my $str;my @data = @_;
 foreach $str (@data) {
  $str =~ s/(\A|[^\r])\n/$1\r\n/sg;
  $str =~ s/^\./../mg;
 }
 print $s @data;
 return 1;
}

=item SendLineEx

 SendLineEx(@strings)

Prints the strings to the socket. Adds an end-of-line character at the end.
Changes all end-of-lines to C<\r\n>. Doesn't encode the data!

UNLESS YOU ARE ABSOLUTELY SURE YOU KNOW WHAT YOU ARE DOING
YOU SHOULD USE SendEnc() INSTEAD!

Returns 1 if successfull.

=cut

sub SendLineEx {
 push @_, "\r\n";
 goto &SendEx;
}


=item Part

 Part( I<description>, I<ctype>, I<encoding>, I<disposition> [, I<content_id>]);
 Part( [description => "desc"], [ctype], [encoding], [disposition], [content_id]});

 Prints a part header for the multipart message.
 The undef or empty variables are ignored.

=over 2

=item description

The title for this part.

=item ctype

the content type (MIME type) of this part. May contain some other
parameters, such as B<charset> or B<name>.

Defaults to "application/octet-stream".

=item encoding

the encoding used for this part of message. Eg. Base64, Uuencode, 7BIT
...

Defaults to "7BIT".

=item disposition

This parts disposition. Eg: 'attachment; filename="send.pl"'.

Defaults to "attachment". If you specify "none" or "", the
Content-disposition: line will not be included in the headers.

=item content_id

The content id of the part, used in multipart/related.
If not specified, the header is not included.

=back

Returns the Mail::Sender object if successfull, negative error code if not.

=cut

sub Part {
 my $self = shift;
 local $_;
 if (! $self->{'multipart'}) { return $self->{'error'}=NOTMULTIPART; }
 $self->EndPart();
 $self->{part} = 1;


 my ($description, $ctype, $encoding, $disposition, $content_id);
 if (ref $_[0] eq 'HASH') {
  my $hash=$_[0];
  $description=$hash->{description};
  $ctype=$hash->{ctype};
  $encoding=$hash->{encoding};
  $disposition=$hash->{disposition};
  $content_id = $hash->{content_id};
 } else {
  ($description, $ctype, $encoding, $disposition, $content_id) = @_;
 }

 $ctype="application/octet-stream" unless defined $ctype;
 $disposition = "attachment" unless defined $disposition;
 $encoding="7BIT" unless defined $encoding;

 # print the last incomplete chunk from previous part
 if ($self->{buffer}) {
  my $code = $self->{code};
  my $s=$self->{"socket"};
  print $s (&$code($self->{buffer}));
  delete $self->{buffer};
 }

 my $code;

 undef $self->{'chunk_size'};
 if ($encoding =~ /Base64/i) {
  $self->{'code'}=\&enc_base64;
  $self->{'chunk_size'} = $enc_base64_chunk;
 } elsif ($encoding =~ /Quoted[_\-]print/i) {
  $self->{'code'}=\&enc_qp;
 } else {
  $self->{'code'}=\&enc_plain;
 }


 $self->Send("Content-type: $ctype\r\n");
 if ($description) {$self->Send("Content-description: $description\r\n");}
 $self->Send("Content-transfer-encoding: $encoding\r\n");
 $self->Send("Content-disposition: $disposition\r\n") unless $disposition eq '' or uc($disposition) eq 'NONE';
 $self->Send("Content-ID: <$content_id>\r\n") if (defined $content_id);
 $self->SendLine;
 return $self;
}


=item Body

 Body([charset [, encoding [, content-type]]]);
 Body({charset => '...', encoding => '...', ctype => '...', msg => '...');

Sends the head of the multipart message body. You can specify the
charset and the encoding. Default is "US-ASCII","7BIT",'text/plain'.

If you pass undef or zero as the parameter, this function uses the default
value:

    Body(0,0,'text/html');

Returns the Mail::Sender object if successfull, negative error code if not.

=cut

sub Body {
	my $self = shift;
	if (! $self->{'multipart'}) { return $self->{'error'}=NOTMULTIPART; }
	my $hash;
	$hash = shift() if (ref $_[0] eq 'HASH');
	my $charset = shift || $hash->{charset} || 'US-ASCII';
	my $encoding = shift || $hash->{encoding} || $self->{'encoding'} || '7BIT';
	my $ctype = shift || $hash->{ctype} || $self->{'ctype'} || 'text/plain';
	$self->Part("Mail message body","$ctype; charset=$charset",
		$encoding, 'inline');
	$self->SendEnc($hash->{msg}) if defined $hash->{msg};
	return $self;
}

=item SendFile

Alias to Attach()

=item Attach

 Attach( I<description>, I<ctype>, I<encoding>, I<disposition>, I<file>);
 Attach( { [description => "desc"] , [ctype => "ctype"], [encoding => "encoding"],
             [disposition => "disposition"], file => "file"});

 Sends a file as a separate part of the mail message. Only in multipart mode.

=over 2

=item description

The title for this part.

=item ctype

the content type (MIME type) of this part. May contain some other
parameters, such as B<charset> or B<name>.

Defaults to "application/octet-stream".

=item encoding

the encoding used for this part of message. Eg. Base64, Uuencode, 7BIT
...

Defaults to "Base64".

=item disposition

This parts disposition. Eg: 'attachment; filename="send.pl"'. If you use
'attachment; filename=*' the * will be replaced by the respective names
of the sent files.

Defaults to "attachment; filename=*". If you do not want to include this header use
"" as the value.

=item file

The name of the file to send or a 'list, of, names' or a
['reference','to','a','list','of','filenames']. Each file will be sent as
a separate part.

=item content_id

The content id of the message part. Used in multipart/related.

 Special values:
  "*" => the name of the file
  "#" => autoincremented number (starting from 0)

=back

Returns the Mail::Sender object if successfull, negative error code if not.

=cut
sub SendFile {
 my $self = shift;
 local $_;
 if (! $self->{'multipart'}) { return $self->{'error'}=NOTMULTIPART; }
 if (! $self->{'socket'}) { return $self->{'error'}=NOTCONNECTED; }

 my ($description, $ctype, $encoding, $disposition, $file, $content_id, @files);
 if (ref $_[0] eq 'HASH') {
  my $hash=$_[0];
  $description=$hash->{description};
  $ctype=$hash->{ctype};
  $encoding=$hash->{encoding};
  $disposition=$hash->{disposition};
  $file=$hash->{file};
  $content_id=$hash->{content_id};
 } else {
  ($description, $ctype, $encoding, $disposition, $file, $content_id) = @_;
 }
 return ($self->{'error'}=NOFILE) unless $file;

 if (ref $file eq 'ARRAY') {
  @files=@$file;
 } elsif ($file =~ /,/) {
  @files=split / *, */,$file;
 } else {
  @files = ($file);
 }
 foreach $file (@files) {
  return $self->{'error'}=FILENOTFOUND($file) unless ($file =~ /^&/ or -e $file);
 }

 $disposition = "attachment; filename=*" unless defined $disposition;
 $encoding='Base64' unless $encoding;

 my $code;
 if ($encoding =~ /Base64/i) {
  $code=\&enc_base64;
 } elsif ($encoding =~ /Quoted[_\-]print/i) {
  $code=\&enc_qp;
 } else {
   $code=\&enc_plain;
 }
 $self->{'code'}=$code;

 if ($self->{buffer}) {
  my $code = $self->{code};
  my $s=$self->{'socket'};
  print $s (&$code($self->{buffer}));
  delete $self->{buffer};
 }

 foreach $file (@files) {
  my $cnt='';
  my $name =  basename $file;
  my $fctype = $ctype ? $ctype : GuessCType $file;
  $self->EndPart();
  $self->Send("Content-type: $fctype; name=\"$name\"\r\n"); # "; type=Unknown"
  if ($description) {$self->Send("Content-description: $description\r\n");}
  $self->Send("Content-transfer-encoding: $encoding\r\n");
  if ($disposition =~ /^(.*)filename=\*(.*)$/i) {
   $self->Send("Content-disposition: ${1}filename=\"$name\"$2\r\n");
  } elsif ($disposition and uc($disposition) ne 'NONE') {
   $self->Send("Content-disposition: $disposition\r\n");
  }
  if ($content_id) {
    if ($content_id eq '*') {
     $self->Send("Content-ID: <$name>\r\n");
    } elsif ($content_id eq '#') {
     $self->Send("Content-ID: <id".$self->{idcounter}++.">\r\n");
    } else {
     $self->Send("Content-ID: <$content_id>\r\n");
    }
  }
  $self->SendLine;
  my $FH = new FileHandle;
  open $FH, "<$file";
  binmode $FH unless $fctype =~ m#^text/#i and $encoding =~ /Quoted[_\-]print|Base64/i;

  my $mychunksize = $chunksize;
  $mychunksize = $chunksize64 if lc($encoding) eq "base64";
  my $s;
  $s = $self->{'socket'};
  while (read $FH, $cnt, $mychunksize) {
   print $s (&$code($cnt));
  }
  close $FH;
 }
 $self->SendLine();
 return $self;
}

sub Attach; *Attach = \&SendFile;

=item Close

 $sender->Close;

Close and send the mail. This method should be called automatically when destructing
the object, but you should call it yourself just to be sure it gets called.
And you should do it as soon as possible to close the connection and free the socket.

The mail is being sent to server, but is not processed by the server
till the sender object is closed!

Returns the Mail::Sender object if successfull, negative error code if not.

=cut

sub EndPart {
 my $self = shift;
# return unless $self->{part};
 my $s = $self->{'socket'};
 if ($self->{buffer}) {
  my $code = $self->{code};
  if (defined $code) {
	  print $s (&$code($self->{buffer}));
  } else {
	  print $s ($self->{buffer});
  }
  delete $self->{buffer};
 }
 print $s "\r\n--",$self->{'boundary'},"\r\n";
 undef $self->{part};
 return $self;
}

sub Close {
 my $self = shift;
 local $_;
 my $s;
 $s = $self->{'socket'};
 return 0 unless $s;
 if ($self->{'multipart'}) {
  if ($self->{buffer}) {
   my $code = $self->{code};
   print $s (&$code($self->{buffer}));
   delete $self->{buffer};
  }
  print $s "\r\n--",$self->{'boundary'},"--\r\n";
 }
 print $s "\r\n.\r\n";

 $_ = get_response($s); if (/^[45]\d* (.*)$/) { close $s; return $self->{'error'}=TRANSFAILED($1); }

 $_ = send_cmd $s, "quit";

 close $s;
 delete $self->{'socket'};
 delete $self->{'debug'};
 return $self;
}

=item Cancel

 $sender->Cancel;

Cancel an opened message.

SendFile and other methods may set $sender->{'error'}.
In that case "undef $sender" calls C<$sender->>Cancel not C<$sender->>Close!!!

Returns the Mail::Sender object if successfull, negative error code if not.

=cut
sub Cancel {
 my $self = shift;
 my $s;
 $s = $self->{'socket'};
 close $s;
 delete $self->{'socket'};
 delete $self->{'error'};
 return $self;
}

sub DESTROY {
 my $self = shift;
 if (defined $self->{'socket'}) {
  if ($self->{'error'}) {
   $self->Cancel;
  } else {
   $self->Close;
  }
 }
}

sub MessageID {
	my $from = shift;
	my ($sec,$min,$hour,$mday,$mon,$year)
		= gmtime(time);
	$mon++;$year+=1900;

	return sprintf "%04d%02d%02d_%02d%02d%02d_%06d.%s",
	$year,$mon,$mday,$hour,$min,$sec,rand(100000),
	$from;

}


#====== Debuging bazmecks

$debug_code = <<'*END*';
package Mail::Sender::DBIO;
use IO::Handle;
use Tie::Handle;
@Mail::Sender::DBIO::ISA = qw(Tie::Handle);

sub TIEHANDLE {
	my ($pkg,$socket,$debughandle, $mayclose) = @_;
	return bless [$socket,$debughandle,1, $mayclose], $pkg;
}

sub PRINT {
	my $self = shift;
	my $text = join(($\ || ''), @_);
	$self->[0]->print($text);
	$text =~ s/\x0D\x0A(?=.)/\x0D\x0A<< /g;
	$text = "<< ".$text if $self->[2];
	$self->[2] = ($text =~ /\x0D\x0A$/);
	$self->[1]->print($text);
}

sub READLINE {
	my $self = shift();
	my $socket = $self->[0];
	my $line = <$socket>;
	$self->[1]->print(">> $line") if defined $line;
	return $line;
}

sub CLOSE {
	my $self = shift();
	$self->[0]->close();
	$self->[1]->close() if $self->[3];
#	return $self->[0];
}
*END*

my $pseudo_handle_code = <<'*END*';
package Mail::Sender::IO;
use IO::Handle;
use Tie::Handle;
@Mail::Sender::IO::ISA = qw(Tie::Handle);

sub TIEHANDLE {
	my ($pkg,$sender) = @_;
	return bless [$sender, $sender->{Part}], $pkg;
}

sub PRINT {
	my $self = shift;
	$self->[0]->SendEnc(@_);
}

sub PRINTF {
	my $self = shift;
	my $format = shift;
	$self->[0]->SendEnc( sprintf $format, @_);
}

sub CLOSE {
	my $self = shift();
	if ($self->[1]) {
		$self->[1]->EndPart();
	} else {
		$self->[0]->Close();
	}
}
*END*

=item GetHandle

Returns a "filehandle" to which you can print the message or file to attach or whatever.
The data you print to this handle will be encoded as necessary. Closing this handle closes
either the message (for single part messages) or the part.

	$sender->Open({...});
	my $handle = $sender->GetHandle();
	print $handle "Hello world.\n"
	my ($mday,$mon,$year) = (localtime())[3,4,5];
	printf $handle "Today is %04d/%02d/%02d.", $year+1900, $mon+1, $mday;
	close $handle;

P.S.: There is a big difference between the handle stored in $sender->{socket} and the handle
returned by this function ! If you print something to $sender->{socket} it will be sent to the server
without any modifications, encoding, escaping, ...
You should NOT touch the $sender->{socket} unless you really really know what you are doing.

=cut
package Mail::Sender;
sub GetHandle {
	my $self = shift();
	unless (defined @Mail::Sender::IO::ISA) {
		eval "use Symbol;";
		eval $pseudo_handle_code;
	}
	my $handle = gensym();
	tie *$handle, 'Mail::Sender::IO', $self;
	return $handle;
}

=item @Mail::Sender::Errors

Contains the description of errors returned by functions in Mail::Sender.

Usage: @Mail::Sender::Errors[$sender->{error}]

=back

=head1 FUNCTIONS

=over 4

=item GuessCType

	$ctype = GuessCType $filename;

Guesses the content type based on the filename (actually ... the extension).

=back

=head1 CONFIG

If you create a file named Sender.config in the same directory where
Sender.pm resides, this file will be "require"d as soon as you "use
Mail::Sender" in your script. Of course the Sender.config MUST "return a
true value", that is it has to be succesfully compiled and the last
statement must return a true value. You may use this to forbide the use
of Mail::Sender to some users.

You may define the default settings for new Mail::Sender objects and do
a few more things.

The default options are stored in hash %Mail::Sender::default. You may
use all the examples you'd use in C<new>, C<Open>, C<OpenMultipart>,
C<MailMsg> or C<MailFile>.

 Eg.
  %default = (
    smtp => 'mail.mccann.cz',
    from => Win32::LoginName.'@mccann.cz',
    client => Win32::NodeName.'mccann.cz'
  );
  # of course you will use your own mail server here !

The other options you may set here (or later of course) are
$Mail::Sender::SITE_HEADERS and $Mail::Sender::NO_X_MAILER.

The $Mail::Sender::SITE_HEADERS may contain headers that will be added
to each mail message sent by this script, the $Mail::Sender::NO_X_MAILER
disables the header item specifying that the message was sent by
Mail::Sender.

!!! $Mail::Sender::SITE_HEADERS may NEVER end with \r\n !!!

If you want to set the $Mail::Sender::SITE_HEADERS for every script sent
from your server without your users being able to change it you may use
this hack:

 $loginname = something_that_identifies_the_user();
 *Mail::Sender::SITE_HEADERS = \"X-Sender: $loginname via $0";


You may even "install" your custom function that will be evaluated for
each message just before contacting the server. You may change all the
options from within as well as stop sending the message.

All you have to do is to create a function named SiteHook in
Mail::Sender package. This function will get the Mail::Sender object as
its first argument. If it returns a TRUE value the message is sent,
if it returns FALSE the sending is canceled and the user gets
"Site specific error" error message.

If you want to give some better error message you may do it like this :

 sub SiteHook {
  my $self = shift;
  if (whatever($self)) {
    $self->{'error'} = SITEERROR;
    $Mail::Sender::Error = "I don't like this mail";
    return 0
  } else {
    return 1;
  }
 }


This example will ensure the from address is the users real address :

 sub SiteHook {
  my $self = shift;
  $self->{fromaddr} = getlogin.'@yoursite.com';
  $self->{from} = getlogin.'@yoursite.com';
  1;
 }

Please note that at this stage the from address is in two different
object properties.

$self->{from} is the address as it will appear in the mail, that is
it may include the full name of the user or any other comment
( "Jan Krynicky <jenda@krynicky.cz>" for example), while the
$self->{fromaddr} is realy just the email address per se and it will
be used in conversation with the SMTP server. It must be without
comments ("jenda@krynicky.cz" for example)!


Without write access to .../lib/Mail/Sender.pm or
.../lib/Mail/Sender.config your users will then be unable to get rid of
this header. Well ... everything is doable, if he's cheeky enough ... :-(

So if you take care of some site with virtual servers for several
clients and implement some policy via SiteHook() or
$Mail::Sender::SITE_HEADERS search the clients' scripts for "SiteHook"
and "SITE_HEADERS" from time to time. To see who's cheating.

=head1 EXAMPLES

 use Mail::Sender;

 #$sender = new Mail::Sender { from => 'somebody@somewhere.com',
    smtp => 'mail.yourISP.com', boundary => 'This-is-a-mail-boundary-435427'};
 # # if you do not care about errors. (But you should!)
 # # otherwise use
 #
 ref ($sender = new Mail::Sender { from => 'somebody@somewhere.com',
       smtp => 'mail.yourISP.com', boundary => 'This-is-a-mail-boundary-435427'})
 or die "Error($sender) : $Mail::Sender::Error\n";

 ref $sender->Open({to => 'friend@other.com', subject => 'Hello dear friend'})
	 or die "Error: $Mail::Sender::Error\n";
 my $FH = $sender->GetHandle();
 print $FH "How are you?\n\n";
 print $FH <<'*END*';
 I've found these jokes.

  Doctor, I feel like a pack of cards.
  Sit down and I'll deal with you later.

  Doctor, I keep thinking I'm a dustbin.
  Don't talk rubbish.

 Hope you like'em. Jenda
 *END*

 $sender->Close;
 # or
 # close $FH;

###

 $sender->Open({to => 'mama@home.org, papa@work.com',
                cc => 'somebody@somewhere.com',
                subject => 'Sorry, I'll come later.'});
 $sender->SendLineEnc("I'm sorry, but due to a big load of work,
    I'll come at 10pm at best.");
 $sender->SendLineEnc("\nHi, Jenda");

 $sender->Close;

###

 $sender->OpenMultipart({to => 'Perl-Win32-Users@activeware.foo',
                         subject => 'Mail::Sender.pm - new module'});
 $sender->Body;
 $sender->SendEnc(<<'*END*');
 Here is a new module Mail::Sender.
 It provides an object based interface to sending SMTP mails.
 It uses a direct socket connection, so it doesn't need any
 additional program.

 Enjoy, Jenda
 *END*
 $sender->Attach(
  {description => 'Perl module Mail::Sender.pm',
   ctype => 'application/x-zip-encoded',
   encoding => 'Base64',
   disposition => 'attachment; filename="Sender.zip"; type="ZIP archive"',
   file => 'sender.zip'
  });
 $sender->Close;

###

 $sender->OpenMultipart({to => 'Perl-Win32-Users@activeware.foo',
                         subject => 'Mail::Sender.pm - new version'});
 $sender->Body({ msg => <<'*END*' });
 Here is a new module Mail::Sender.
 It provides an object based interface to sending SMTP mails.
 It uses a direct socket connection, so it doesn't need any
 additional program.

 Enjoy, Jenda
 *END*
 $sender->Attach(
  {description => 'Perl module Mail::Sender.pm',
   ctype => 'application/x-zip-encoded',
   encoding => 'Base64',
   disposition => 'attachment; filename="Sender.zip"; type="ZIP archive"',
   file => 'sender.zip'
  });
 $sender->Close;

### A nice way to use the module is:

 use Mail::Sender;
 eval {
 (new Mail::Sender)
 	->OpenMultipart({smtp=> 'jenda.krynicky.cz', to => 'jenda@krynicky.cz',subject => 'Mail::Sender.pm - new version'})
 	->Body({ msg => <<'*END*' })
 Here is a new module Mail::Sender.
 It provides an object based interface to sending SMTP mails.
 It uses a direct socket connection, so it doesn't need any
 additional program.

 Enjoy, Jenda
 *END*
 	->Attach({
 		description => 'Perl module Mail::Sender.pm',
 		ctype => 'application/x-zip-encoded',
 		encoding => 'Base64',
 		disposition => 'attachment; filename="Sender.zip"; type="ZIP archive"',
 		file => 'W:\jenda\packages\Mail\Sender\Mail-Sender-0.7.13.tar.gz'
 	})
 	->Close();
 } or print "Error sending mail: $Mail::Sender::Error\n";

###

If everything you need is to send a simple message you may use:

 use Mail::Sender;

 ref ($sender = new Mail::Sender({from => 'somebody@somewhere.com',smtp
 => 'mail.yourISP.com'})) or die "$Mail::Sender::Error\n";

 (ref ($sender->MailMsg({to =>'Jenda@Krynicky.czX', subject => 'this is a test',
                         msg => "Hi Johnie.\nHow are you?"}))
  and print "Mail sent OK."
 )
 or die "$Mail::Sender::Error\n";

or

 use Mail::Sender;

 eval {
 	(new Mail::Sender)
 	->MailMsg({smtp => 'mail.yourISP.com',
		from => 'somebody@somewhere.com',
		to =>'Jenda@Krynicky.czX',
		subject => 'this is a test',
		msg => "Hi Johnie.\nHow are you?"})
 }
 or die "$Mail::Sender::Error\n";


If you want to attach some files:

 use Mail::Sender;

 ref ($sender = new Mail::Sender({from => 'somebody@somewhere.com',smtp
 => 'mail.yourdomain.com'})) or die "$Mail::Sender::Error\n";

 (ref ($sender->MailFile(
  {to =>'you@address.com', subject => 'this is a test',
   msg => "Hi Johnie.\nI'm sending you the pictures you wanted.",
   file => 'image1.jpg,image2.jpg'
  }))
  and print "Mail sent OK."
 )
 or die "$Mail::Sender::Error\n";
 __END__

If you want to send a HTML mail:

 use Mail::Sender;
 open IN, $htmlfile or die "Cannot open $htmlfile : $!\n";
 $sender = new Mail::Sender {smtp => 'mail.yourdomain.com'};
 $sender->Open({ from => 'your@address.com', to => 'other@address.com', subject => 'HTML test',
        headers => "MIME-Version: 1.0\r\nContent-type: text/html\r\nContent-Transfer-Encoding: 7bit"
 }) or die $Mail::Sender::Error,"\n";

 while (<IN>) { $sender->Send($_) };
 close IN;
 $sender->Close();
 __END__

If you want to send a HTML with some inline images :

	use strict;
	use Mail::Sender;
	my $recipients = 'somebody@somewhere.com';
	my $sender = new Mail::Sender {smtp => 'your.mailhost.com'};
	if (ref $sender->OpenMultipart({
		from => 'itstech2@gate.net', to => $recipients,
		subject => 'Embedded Image Test',
		boundary => 'boundary-test-1',
		type => 'multipart/related'})) {
		$sender->Attach(
			 {description => 'html body',
			 ctype => 'text/html; charset=us-ascii',
			 encoding => '7bit',
			 disposition => 'NONE',
			 file => 'test.html'
		});
		$sender->Attach({
			description => 'ed\'s gif',
			ctype => 'image/gif',
			encoding => 'base64',
			disposition => "inline; filename=\"apache_pb.gif\";\r\nContent-ID: <img1>",
			file => 'apache_pb.gif'
		});
		$sender->Close() or die "Close failed! $Mail::Sender::Error\n";
	} else {
		die "Cannot send mail: $Mail::Sender::Error\n";
	}

In the HTML you'll have this :
 ... <IMG src="cid:img1"> ...

Please keep in mind that the image name is unimportant, the Content-ID is what counts!

# or using the eval{ $obj->Method()->Method()->...->Close()} trick ...

	use Mail::Sender;
	eval {
	(new Mail::Sender)
		->OpenMultipart({
			to => 'someone@somewhere.com',
			subject => 'Embedded Image Test',
			boundary => 'boundary-test-1',
			type => 'multipart/related'
		})
		->Attach({
			description => 'html body',
			ctype => 'text/html; charset=us-ascii',
			encoding => '7bit',
			disposition => 'NONE',
			file => 'c:\temp\zk\HTMLTest.htm'
		})
		->Attach({
			description => 'Test gif',
			ctype => 'image/gif',
			encoding => 'base64',
			disposition => "inline; filename=\"test.gif\";\r\nContent-ID: <img1>",
			file => 'test.gif'
		})
		->Close()
	}
	or die "Cannot send mail: $Mail::Sender::Error\n";


If you want to send a mail with an attached file you just got from a HTML form:

 #!perl

 use CGI;
 use Mail::Sender;

 $query = new CGI;

 # uploading the file...
 $filename = $query->param('mailformFile');
 if ($filename ne ""){
  $tmp_file = $query->tmpFileName($filename);
 }

 $sender = new Mail::Sender {from => 'script@krynicky.cz',smtp => 'mail.krynicky.czX'};
 $sender->OpenMultipart({to=> 'jenda@krynicky.czX',subject=> 'test CGI attach'});
 $sender->Body();
 $sender->Send(<<"*END*");
 This is just a test of mail with an uploaded file.

 Jenda
 *END*
 $sender->SendFile(
          {encoding => 'Base64',
    description => $filename,
    ctype => $query->uploadInfo($filename)->{'Content-Type'},
    disposition => "attachment; filename = $filename",
           file => $tmp_file
          });
 $sender->Close();

 print "Content-type: text/plain\n\nYes, it's sent\n\n";


If you want to confirm reading you add :

	headers => "X-Confirm-Reading-To: $from_address"

if you want delivery report you add :

	headers => "Return-receipt-to: $from_address"

if both :

	headers => "X-Confirm-Reading-To: $from_address\r\nReturn-receipt-to: $from_address"


=head2 WARNING

DO NOT mix Open(Multipart)|Send(Line)(Ex)|Close with MailMsg or MailFile.
Both Mail(Msg/File) close any Open-ed mail.
Do not try this:

 $sender = new Mail::Sender ...;
 $sender->OpenMultipart...;
 $sender->Body;
 $sender->Send("...");
 $sender->MailFile({file => 'something.ext');
 $sender->Close;

This WON'T work!!!

=head1 BUGS

I'm sure there are many. Please let me know if you find any.

The problem with multiline responses from some SMTP servers (namely qmail) is solved.

=head1 DISCLAIMER

This module is based on SendMail.pm Version : 1.21 that appeared in
Perl-Win32-Users@activeware.com mailing list. I don't remember the name
of the poster and it's not mentioned in the script. Thank you mr. C<undef>.

=head1 AUTHOR

Jan Krynicky <Jenda@Krynicky.cz>
http://Jenda.Krynicky.cz

With help of Rodrigo Siqueira <rodrigo@insite.com.br>,
Ed McGuigan <itstech1@gate.net>,
John Sanche <john@quadrant.net>
and others.

=head1 COPYRIGHT

Copyright (c) 1997-2002 Jan Krynicky <Jenda@Krynicky.cz>. All rights reserved.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. There is only one aditional condition, you may
NOT use this module for SPAMing! NEVER! (see http://spam.abuse.net/ for definition)

=cut
