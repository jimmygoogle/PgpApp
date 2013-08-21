#!/usr/bin/perl -w
use strict;

use Getopt::Long;
use Cwd;
use Data::Dumper;
use InfoArmor;

main();

sub main
{	
	my $options = setParameters();

	if(
		$options->{'help'} 
		|| 
		$options->{'wrongParams'}
	)
	{
		displayUsage();
	}
	
	else
	{
		my $ia = InfoArmor->new(('debug' => $options->{'debug'}));
		
		$ia->processData($options);
	}

}

sub displayUsage 
{
	print qq|
Usage: $0 [options]

Options:

It needs interval and type to run:
	--help				display this usage message.
	--debug 			this will enable or disable printing debug information to STDERR
	--scp_host 			this is the destination host which we will transfer the file securely to
	--scp_username 		this is the username to use when transferring the file
	--scp_password 		this is the password that will be used when transferring the file
	--scp_identityf 	this is an optional field if you wish to use, if used and set id like this to be the rsa private key to use
	--scp_destpath 		this is the destination path on the remote server where we expect to transfer the file to
	--file 				this will be the file in which we expect to process (default parsefile.xml.gpg)
	--archive 			this flag when set should move the encrypted output file to the archive directory
	--recipient 		this defines which gpg key to use (defaults to anthonynowak\@infoarmor.com)
|;
}

sub setParameters 
{	
	my $options = {};
		
    GetOptions (
    $options,
    
    'debug',
    'scp_host:s',
	'scp_username:s',
	'scp_password:s',
	'scp_identityf:s',
	'scp_destpath:s',
	'file:s',
	'archive',
	'recipient:s',
    'help'
    
    ); 
    
    ## make sure we set everything that is needed
    if
    (
    	!$options->{'scp_host'}
    	&&
        !$options->{'scp_password'}
    	&&
        !$options->{'scp_username'}
    	&&
        !$options->{'scp_destpath'}
	    &&
    )
    {
    	$options->{'wrongParams'}++;	
    }
    
    ## set working directory
    $options->{'workingBaseDirectory'} = getcwd;

	## file to be processed
    $options->{'file'} ||= 'parsefile.xml.gpg';
       
	## set full path for encrytped file
    $options->{'workingEncryptedFile'} = qq|$options->{'workingBaseDirectory'}/inbound/$options->{'file'}|;
 	
 	## set archive location
    $options->{'archiveLocation'} = qq|$options->{'workingBaseDirectory'}/archive/|;
    
    ## set temp location for decrypted file
    $options->{'tempDecryptedFile'} =  qq|$options->{'workingBaseDirectory'}/a.out|;
    
    ## gpg key to use
    $options->{'recipient'} ||= 'anthonynowak@infoarmor.com';
    
    ## get current date
    my $currentDate = qx|date +%Y%m%d|;
    chomp($currentDate);
    $options->{'currentDate'} = $currentDate;
    
    ## get pass phrase for decryption
    my $passPhrase = qx|cat /$options->{'workingBaseDirectory'}/encryption/passphrase.txt|;
    chomp($passPhrase);
   	$options->{'passPhrase'} = $passPhrase;

    return($options);
}      
