use Cwd;
use FileHandle;
use Socket;

sub Ignore {
    print "\nDo you want to change the setting or use this one in spite of the errors?\n\t(C)hange / (U)se : ";
    local $_;
    while (<STDIN>) {
        return 1 if /^u$/i;
        return if /^c$/i;
        print "\t(C)hange / (U)se : ";
    }
    exit;
}

print "\nSpecify defaults for Mail::Sender? (y/N) ";
$res = <STDIN>;
exit unless $res =~ /^y$/i;

print "\n\t...Defaults values will be saved to .../lib/Mail/Sender.config\n";

mkdir 'blib',0777;
mkdir 'blib/lib',0777;
mkdir 'blib/lib/Mail',0777;

while (1) {
 print "\nDefault SMTP server (hostname or IP address)\n\n\t: ";
 $smtp=<STDIN>;chomp $smtp;
 last unless $smtp;

 print "\n\t...Trying $smtp...";
 
 my $proto = (getprotobyname('tcp'))[2];
 my $port  = getservbyname('smtp', 'tcp');

 $smtp =~ s/^\s+//g; # remove spaces around $smtp
 $smtp =~ s/\s+$//g;

 my $smtpaddr = ($smtp =~
  /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/)
  ? pack('C4',$1,$2,$3,$4)
  : (gethostbyname($smtp))[4];

 unless ($smtpaddr) {
  print "FAILED\n\t...cannot find server '$smtp' !!!\n";
  if (Ignore()) {last} else {next};
  next;
 }

 my $s = &FileHandle::new(FileHandle);

 if (!socket($s, AF_INET, SOCK_STREAM, $proto)) {
  die <<"*END*";
Call to socket() failed. You either do not have enough permissions
or something really strange happened. Until you fix this neither Mail::Sender
nor any other network related module will work. :-((
*END*
  if (Ignore()) {last} else {next};
 }

 if (!connect($s, pack('Sna4x8', &AF_INET, $port, $smtpaddr))) {
  print "FAILED\n\t...the server is either down or doesn't accept connections\n\ton port 25(SMTP).";
  if (Ignore()) {last} else {next};
 }

 my($oldfh) = select($s); $| = 1; select($oldfh);

 $_ = <$s>;
 if (/^[45]\d*\s*(.*)$/) {
  close $s;
  print "FAILED\n\t...the server replied '$1'.\n";
  if (Ignore()) {last} else {next};
 }

 print $s "helo localhost\r\n";
 $_ = <$s>;
 if (/^[45]\d*\s*(.*)$/) {
  close $s;
  print <<"*END*";
To my greeting the server replied '$1'.
It probably meens that you will have to specify the client name
when connecting to this server. You should specify the default
client name later during this configuration, otherwise you will have
to include parameter client=> in every "new Mail::Sender" call.
*END*

  if (Ignore()) {last} else {next};
 }

 print $s "quit\r\n";
 print "successful :-)\n";
 last;

}

$default{smtp} = "'$smtp'";

print <<"*END*";

*********************************************************************
**** ALL of the following Defaults are interpreted as perl code *****
*********************************************************************

*********************************************************************
Default FROM value (must be perl code / ENTER for none):

\tExamples:
\t   *   'user\@yourdomain.com'
\t   *   getlogin() . '\@yourdomain.com'
\t   *   'Your Name <yourname\@yourdomain.com>'\n
*END*
print "\t: ";
$default{from}=<STDIN>;
chomp $default{from};delete $default{from} unless $default{from};

print "\n*********************************************************************\n";
print "Default for REPLY-TO field (must be perl code / ENTER for none):\n\n\t: ";
$default{replyto}=<STDIN>;
chomp $default{replyto};delete $default{replyto} unless $default{replyto};

print "\n*********************************************************************\n";
print "Default for CC field (must be perl code / ENTER for none):\n\n\t: ";
$default{cc}=<STDIN>;
chomp $default{cc};delete $default{cc} unless $default{cc};

print "\n*********************************************************************\n";
print "Default for BCC field (must be perl code / ENTER for none):\n\n\t: ";
$default{bcc}=<STDIN>;
chomp $default{bcc};delete $default{bcc} unless $default{bcc};

print "\n*********************************************************************\n";
print "Default name of the client MACHINE used when connecting\nto the SMTP server (must be perl code / ENTER for none):\n\n\t: ";
$default{client}=<STDIN>;
chomp $default{client};delete $default{client} unless $default{client};

print "\n*********************************************************************\n";
print "Default additional headers (must be perl code / ENTER for none):\n\n\t: ";
$default{headers}=<STDIN>;
chomp $default{headers};delete $default{headers} unless $default{headers};

print "\n*********************************************************************\n";
print "Default encoding of message bodies (N)one, (Q)uoted-printable, (B)ase64:\n\n\t: ";
while (<STDIN>) {
 chomp;
 /^q$/i and $default{encoding} = "'Quoted-printable'" and last;
 /^b$/i and $default{encoding} = "'Base64'" and last;
 /^n$/i and last;
}

print "\n*********************************************************************\n";
print "Default charset of message bodies (must be perl code / ENTER for none):\n\n\t: ";
$default{charset}=<STDIN>;
chomp $default{charset};
unless ($default{charset}) {
 delete $default{charset}
} else {
 $default{charset} =~ /^[\w\d_-]+$/ and $default{charset} = "'$default{charset}'";
}

print "\n*********************************************************************\n";
print "*********************************************************************\n";

sleep 20;

open CFG, '>blib/lib/Mail/Sender.config';select CFG;
print "### Config file for Mail::Sender\n### generated by Config.PL (".scalar(localtime).")\n\n";

print "%default = (\n";

foreach (keys %default) {
    print "\t$_ => $default{$_},\n";
}

print ");\n\n";

print <<'*END*';
# The contents of this variable will be inserted into the headers of every
# mail message sent by Mail::Sender.
#
#  $Mail::Sender::SITE_HEADERS = "X-Sender: ".getlogin()."\@mysite.com";


# This function will be evaluated for every mail message before contacting the server.
# You may change all the options of the message and even cancel the message.
#
# sub SiteHook {
# }


1;

*END*

close CFG;

print "The defaults were saved into ".getcwd."/blib/lib/Mail/Sender.config
Please review the code in there especialy if 'make test' fails.";

1;
