use inc::Module::Install;

name('Kwiki-Attachments');
author('Sue Spence <sue_cpan@pennine.com>');
abstract('Kwiki File Attachments Plugin');
license('perl');
version_from('lib/Kwiki/Attachments.pm');

requires(qw(
    perl 5.6.1
    Kwiki 0.37
));

check_nmake();

&WriteAll();
