use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'	=> 'Mail::Sender',
    'PREREQ_PM' => {'MIME::Base64' => 0,'MIME::QuotedPrint' => 0},
    'VERSION_FROM' => 'Sender.pm', # finds $VERSION
    'AUTHOR' => 'Jan Krynicky (Jenda@Krynicky.cz)',
    'ABSTRACT' => 'Send mails with attachments through a SMTP server, socket()s based.',
);
