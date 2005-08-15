package Kwiki::Attachments;
use strict;
use warnings;
use Kwiki::Plugin '-Base';
use Kwiki::Installer '-base';
our $VERSION = '0.16';

const class_id => 'attachments';
const class_title => 'File Attachments';
const cgi_class => 'Kwiki::Attachments::CGI';
const config_file => 'attachments.yaml';
const css_file => 'attachments.css';

field 'display_msg';
field files => [];

sub register {
    my $registry = shift;
    $registry->add( action => 'attachments');
    $registry->add( action => 'attachments_upload');
    $registry->add( action => 'attachments_delete');
    $registry->add( toolbar => 'attachments_button', 
                    template => 'attachments_button.html',
                    show_for => ['display'],
                  );
    $registry->add( wafl => file => 'Kwiki::Attachments::Wafl');
    $registry->add( wafl => img =>  'Kwiki::Attachments::Wafl');
    $registry->add( wafl => thumb =>  'Kwiki::Attachments::Wafl');
    $registry->add( preload => 'attachments' );
    $registry->add(widget => 'attachments_widget', 
                   template => 'attachments_widget.html',
                   show_for => [ 'display', 'edit' ],
                  );
}

sub update_metadata {
   # 'touch' page metadata 
   my $page = $self->pages->current;
   $page->metadata->update->store;
}

sub attachments {
    $self->get_attachments( $self->pages->current_id );
    $self->render_screen();
}


sub attachments_upload {
   my $page_id = $self->pages->current_id;
   my $skip_like = $self->config->attachments_skip;
   my $client_file = my $file = CGI::param('uploaded_file');
   $file =~ s/.*[\/\\](.*)/$1/;  # get base filename
   $file =~ tr/a-zA-Z0-9.&+-/_/cs;
   unless ($file){
       $self->display_msg("Please specify a file to upload.");
   }
   else {
      if ($file =~ /$skip_like/i) {
         $self->display_msg("The selected file, $client_file, 
                             was not uploaded because its name matches the 
                             pattern of file names excluded by this wiki.");
      }
      else {
         my $newfile = io->catfile($self->plugin_directory, $page_id, $file);
         local $/;
         my $fh = CGI::upload('uploaded_file');

         if ( $fh ) {
            binmode($fh);
            $newfile->assert->print(<$fh>);
            $newfile->close();
            $self->update_metadata();
            $self->make_thumbnail($newfile);
         } 
      }
   }
   $self->get_attachments( $page_id );
   $self->render_screen;
}

sub make_thumbnail {
   use File::Basename;

   my $file = shift;
   my ($fname, $fpath, $ftype) = fileparse($file, qr(\..*$));
   my $thumb = io->catfile($fpath, "thumb_$fname$ftype");
   
   if (eval { require Imager }) {
      my $found = 0;
      if ($ftype =~ /jpg/i) {
         $found = 1;
      } else {
         for (keys %Imager::format) {
            if ($ftype =~ /$_/oi) {
               $found = 1;
               last;
            }
         }
      }
      if ($found) {
         my $image = Imager->new;
         return unless ref($image);
         $image->read(file=>$file);
         my $thumb_img = $image->scale(xpixels=>80,ypixels=>80);
         $thumb_img->write(file=>$thumb);
      }
   } elsif (eval { require Image::Magick }) {
      my $image = Image::Magick->new;
      return unless ref($image);
      if (!$image->Read($file)) {
         if (!$image->Scale(geometry=>'80x80')) {
            if (!$image->Contrast(sharpen=>"true")) {
               $image->Write($thumb);
            }
         }
      }
   }
}

sub attachments_delete {
    # Remove the attachment and thumbnail, if one exists
    my $page_id = $self->hub->pages->current_id;
    my $base_dir = $self->plugin_directory;
    foreach my $file ( $self->cgi->delete_these_files ) {
        # my $f = $base_dir . '/' . $page_id . '/' . $file;
        my $f = io->catfile($base_dir, $page_id, $file)->pathname;
        if ( -f $f ) {
            unlink $f or die "Unable To Delete: $f";
        }
        my $thumb = io->catfile($base_dir, $page_id, "thumb_$file")->pathname;
        if ( -f $thumb ) {
            unlink $thumb;
        }
    }
    $self->get_attachments( $page_id );
    $self->update_metadata();
    $self->render_screen();
}

sub get_attachments {
    my $page_id = shift;
    my $skip_like = $self->config->attachments_skip;
    my @files;
    my $page_dir = $self->plugin_directory . '/' . $page_id;
    my $count = 0;
    @{$self->{files}} = ();
    if ( opendir( DIR, $page_dir) ) {
        my $file_name;
        while ( $file_name = readdir(DIR) ) {
            next if $file_name =~ /$skip_like/i;
            my $full_name = $page_dir . '/' . $file_name;
            my $thumb = $page_dir . '/' . "thumb_$file_name";
            next unless -f $full_name;
            ( undef, undef, undef, undef, undef, undef, undef,
              my $size,
              undef,
              my $mtime,
              undef, undef, undef ) = stat($full_name);
            push @{$self->{files}}, Kwiki::Attachments::File->new( $file_name,
                                                                   $full_name,
                                                                   $size,
                                                                   $mtime,
                                                                   $thumb);
            $count++;
        }
        closedir DIR;
    }
    return $count;
}

sub file_count {
    return $self->{files} ? (0 + @{$self->{files}}) : 0;
}

package Kwiki::Attachments::CGI;
use base 'Kwiki::CGI';

cgi 'delete_these_files';
cgi 'uploaded_file';

package Kwiki::Attachments::File;
use Spiffy qw(-Base -dumper);

use POSIX qw( strftime );

field 'name';
field 'href';
field 'bytes';
field 'time';
field 'thumb';

sub new() {
    my $class = shift;
    my $self = bless {}, $class;

    my $name = shift;
    my $href = shift;
    my $bytes = shift;
    my $time = shift;
    my $thumb = shift;

    $name = Spoon::Base->html_escape($name);
    $href = Spoon::Base->html_escape($href);

    $self->name( $name );
    $self->href( $href );
    $self->bytes( $bytes );
    $self->time( $time );
    $self->thumb( $thumb );

    return $self;
}

sub date {
     return Kwiki::Page->format_time($self->time);
}

sub size {
    my $size = $self->bytes;
    my $scale = 'B';
    if ( $size > 1024 ) { $size >>= 10; $scale = 'K'; }
    if ( $size > 1024 ) { $size >>= 10; $scale = 'MB'; }
    if ( $size > 1024 ) { $size >>= 10; $scale = 'GB'; }
    return $size . $scale;
}

sub thumbnail {
   # returns nothing if no thumbnail file
   return $self->thumb if (-f $self->thumb) 
}

package Kwiki::Attachments::Wafl;
use base 'Spoon::Formatter::WaflPhrase';

sub html {
   my @args = split( / +/, $self->arguments );
   my $file_name = shift( @args );
   my $desc = @args ? join( ' ', @args ) : $file_name;
   my $base_dir = $self->hub->attachments->plugin_directory;
   my $loc = $base_dir . '/';
   if ( $file_name !~ /\// ) {
      # file is on the current page
      my $page_id = $self->hub->pages->current_id;
      $loc .= $page_id . '/';
   }
   $loc .= $file_name;
   my $thumb = $loc;
   $thumb =~ s|/(?=[^/]*$)|/thumb_|;
   return join('', $self->html_escape($desc), ' (file not found)')
      unless -f $loc;
   if ( $self->method eq "img" ) {
        return join '', 
                    '<img src="', $loc, '" alt="',
                    $self->html_escape($desc), 
                    '" />';
   } elsif ( $self->method eq "file" ) {
       return join '', 
                   '<a href="', $loc, '">',
                   $self->html_escape($desc), 
                   '</a>';
   } else {
       return join '', 
                   '<a href="', $loc, '">',
                   '<img border="0" src="', $thumb, '"',
                   ' alt="', $self->html_escape($desc), '"',
                   ' />',
                   '</a>';
   }
}

1;

package Kwiki::Attachments;

__DATA__

=head1 NAME 

Kwiki::Attachments - Kwiki Page Attachments Plugin

=head1 SYNOPSIS

=over 4

=item 1.
Install Kwiki::Attachments

=item 2.
Run 'kwiki -add Kwiki::Attachments'

=back

=head1 DESCRIPTION

This module gives a Kwiki wiki the ability to upload, store and manage file
attachments on any page. If you have image creation modules such as Imager,
Image::Magick, or Image::GD::Thumbnail installed, then a thumbnail will be
created for every supported image file type that is uploaded. Thumbnails are 
displayed on the attachments page.

This module also provides 3 WAFL directives which can be used to link to or display attachments in a kwiki page.

=over 4

=item *
{file:[page/]filename} creates a link to attachment "filename".

=item *
{img:[page/]filename} displays attachment "filename".

=item *
{thumb:[page/]filename} displays the thumbnail for attachment "filename".

=back

=head1 AUTHOR

Sue Spence <sue_cpan@pennine.com>

This module is based almost entirely on work by
Eric Lowry <eric@clubyo.com> and Brian Ingerson <INGY@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2005. Sue Spence. All rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See http://www.perl.com/perl/misc/Artistic.html

=cut
__config/attachments.yaml__
attachments_dir: attachments
attachments_skip: (^\.)|(^thumb_)|(~$)|(\.bak$)
thumbnail_module: Imager
__css/attachments.css__
table.attachments {
    color: #999;
}
th.delete { text-align: left;width: 15% }
th.file   { text-align: left;width: 35% }
th.size   { text-align: left;width: 15% }
th.date   { text-align: left; }
th.thumb  { text-align: left; }
td.delete { text-align: left;width: 15% }
td.file   { text-align: left;width: 35% }
td.size   { text-align: left;width: 15% }
td.thumb  { text-align: left; }

__template/tt2/attachments_button.html__
<!-- BEGIN attachments_button.html -->
<a href="[% script_name %]?action=attachments&page_name=[% page_uri %]" accesskey="f" title="File Attachments">
[% INCLUDE attachments_button_icon.html %]
</a>
<!-- END attachments_button.html -->
__template/tt2/attachments_button_icon.html__
<!-- BEGIN attachments_button_icon.html -->
Attachments
<!-- END attachments_button_icon.html -->
__icons/gnome/template/attachments_button_icon.html__
<!-- BEGIN attachments_button_icon.html -->
<img src="icons/gnome/image/attachments.png" alt="Attachments" />
<!-- END attachments_button_icon.html -->
__template/tt2/attachments_content.html__
<!-- BEGIN attachments_content.html -->

File Attachments For:
<a href="[% script_name %]?[% page_name %]">[% page_uri %]</a>
<br />

[% IF self.file_count > 0 %]
<br />
<form   method="post" 
        action="[% script_name %]" >
<input  type="hidden" 
        name="action" 
        value="attachments_delete">
<input  type="hidden" 
        name="page_name" 
        value="[% page_uri %]">
<table  class="attachments">
<tr>
<th class="delete">Delete?</th>
<th class="file">File</th>
<th class="size">Size</th>
<th class="date">Uploaded On</th>
</tr>
[% FOR file = self.files %]
<tr>
<td class="delete"><input type="checkbox" name="delete_these_files" value="[% file.name %]"></td>
<td class="file"><a href="[% file.href %]">[% file.name %]</a></td>
<td class="size">[% file.size %]</td>
<td class="date">[% file.date %]</td>
[% IF file.thumbnail %]
<td class="thumb"><a href="[% file.href %]"><img src="[% file.thumbnail %]" border="0" width="80" height="80" alt="[% file.name %]"></a></td>
[% END %]
</tr>
[% END %]
<tr>
<td colspan="99">
<input type="submit" name="Delete" value="Delete">
</td>
</tr>
</table>
</form>
[% END %]
<br />
<form  method="post" 
       action="[% script_name %]" 
       enctype="multipart/form-data" >
<input type="hidden" 
       name="action" 
       value="attachments_upload">
<input type="hidden" name="page_name" value="[% page_uri %]">
File
<input type="file" 
       name="uploaded_file" 
       size="40" 
       maxlength="80" />
<input type="submit" 
       name="Upload" 
       value="Upload">
</form>
<p style="color: red;font-size: larger "> [% self.display_msg %]</p>
<!-- END attachments_content.html -->
__template/tt2/attachments_widget.html__
<!-- BEGIN attachments_widget.html -->
[% count = hub.attachments.get_attachments( page_uri ) -%]
[% IF count %]
<table class="attachments_widget">
<tr><th colspan="2" style="text-align: left">Attachments</th></td>
[% FOR file = hub.attachments.files %]
<tr>
<td><a href="[% file.href %]" title="[% file.size %] - [% file.name %]">[% file.name %]</a></td>
<td>[% file.size %]</td>
</tr>
[% END -%]
</table>
[% END -%]
<!-- END attachments_widgets.html -->
__icons/gnome/image/attachments.png__
iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAABmJLR0QA/wD/AP+gvaeTAAABLUlE
QVR42rWSPW6EMBCFX3KEVDnHlmlpKKjpqVNEOca2nIAmFVus0BYRSpEWpBRuaSzRUJgDWPzMSxOs
hcDuKlIsjeQZz3v+PDLwD8sDwEW8bjXfr9Q+ANydxTOARwBvP2b+NQKe7X0AX1EUUUR4PB65ON80
cMJhGDiOI0WEWmsGQXCRwp/e3XUdu65j3/cUEeZ5fpHiCcDe8zwCoLWWIkIRIQAqpVyutWYYhr8o
8jiOnUBEqJSiUsrlU22L4r0oitUbp9wYM6NYzuIhCAInaNuWIsKqqmYEdV0zTVMOw7BNcTqdCMCJ
D4eDw2+ahn3fU2u9auAoJpMkSWiMYVmWtNY6YRRF3PpUbhbGGBZFwaqqbhLOKOq6dsO6VTijyLLs
T0JHAeATAHe73cu15m88QWrCNHlDUQAAAABJRU5ErkJggg==

