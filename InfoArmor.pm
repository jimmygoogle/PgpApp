package InfoArmor;

use strict;
use GnuPG qw( :algo );
use Mail::RFC822::Address qw(valid);
use XML::Simple;
use XML::Parser;
use Data::Dumper;
use FileHandle;
use DBI;

sub new
{
	my ($class, %data) = @_;

	my $this = {};

	bless $this, $class;

	$this->_initialize(\%data);

	return $this;
}

sub _initialize 
{
   	my ($this, $data) = @_;

	$data ||= {};
	
	for my $key (keys (%$data))
	{
		$this->{'attributes'}->{$key} = $data->{$key};
	}
	
	return($this);    
}

sub processData
{
	my ($this, $options) = @_;
	
	$this->Debug('options=', $options);
	
	my $errors = [];
	
	## process xml file if it decrypts properly
	if ($this->decryptFile($options)) 
	{
		## get hash of XML data
		## this could be changed if the XML result was enormous
		my $xmlData = $this->parseXmlFile($options);
		
		## get total number of records 
		my $totalRecords = scalar(@{$xmlData->{'subscriber'}});
		
		## keep counts of records processed and invalid records
		my $invalidRecordCount 		= 0;
		my $recordsProcessedCount	= 0;
		
		## setup output file
		my $fh = $this->openFileHandle($options);
		
		## print headers
		print $fh qq|email,firstname,lastname,phone\n|;
		
		foreach my $record ( @{$xmlData->{'subscriber'}} )
		{	
			$this->Debug('record is=', $record);
			
			## validate record	
			if($this->recordIsValid($record))
			{
				## get all services for record
				foreach my $services ( keys %{$record->{'options'}} )
				{
					push(@{$record->{'serviceIDs'}}, $record->{'options'}->{$services})
				}
				
				## write to DB
				$this->insertRecord($record);
				
				## write valid records to output file
		    	if (defined $fh) 
	    		{
	        		print $fh qq|$record->{'email'},$record->{'firstname'},$record->{'lastname'},$record->{'phone'}\n|;
	    		}		
			}
		
			else
			{
				push(@{$errors}, $this->validationError());	
				$invalidRecordCount++;	
			}
			
			$recordsProcessedCount++;
			$this->resetValidationError();
		}
		
		$this->closeFileHandle();
	
		## encrypt outbound file
		$this->encryptOutboundFile($options);
		
		## scp outbound file
		$this->transferEncryptedOutboundFile($options);
		
		## cleanup working files
		#$this->cleanupWorkingFiles($options);
		
		## send back report of what was done 
		$this->Output(qq|There were $totalRecords total records. \nThere were $recordsProcessedCount records processed and $invalidRecordCount invalid records|);
	}

	## sent output to
	$this->Output('script options=' . 	 Dumper($options));
	$this->Output('Validation errors=' . Dumper($errors));
	
	## set exit status based on errors from run
	my $exitStatus = 1;
	
	if(!$this->hasErrors())
	{
		$exitStatus = 10;	
	}
	
	$this->Debug('exiting with status=', $exitStatus);
	
	exit($exitStatus);
}

sub decryptFile
{
	my ($this, $options) = @_;
	
	$this->{'attributes'}->{'gpg'} = new GnuPG();
	
	my $status = 1;
	
#	## we need to eval because the gpg call croaks?! on an error
#	## decrypt file for processing
#	eval 
#	{ 
#		$this->{'attributes'}->{'gpg'}->decrypt
#		( 
#			ciphertext  => $options->{'workingEncryptedFile'}, 
#			output 		=> $options->{'tempDecryptedFile'},
#			passphrase 	=> $options->{'passPhrase'}
#		);
#	};
#	
#	## catch error from decrypt call
#	if ($@) 
#	{
#		$this->addErrors(qq|decrypt raised an exception: $@|);
#		$status = 0;
#	} 	
	
	return($status);
}

sub transferEncryptedOutboundFile
{
	my ($this, $options) = @_;

	my $status = 0;
	
	my $command = qq|scp -i $options->{'scp_identityf'} -o 'ConnectTimeout=10' -o 'StrictHostKeyChecking=no' $options->{'encryptedOutboundFile'} $options->{'scp_username'}\@$options->{'scp_host'}:$options->{'scp_destpath'}|;
	
	$this->Debug('running scp command=', $command);
	
	my $scpResponse = `$command 2>&1`;
			
	$this->Debug('scp response=', $scpResponse);
	
	if($scpResponse !~ /error|timed out/i)
	{
		$status++;
	}	
	
	else
	{
		$this->addErrors($scpResponse);
	}
	
	if($options->{'archive'})
	{
		qx|/bin/mv $options->{'encryptedOutboundFile'} $options->{'archiveLocation'}|;
	}
	
	return($status);

}

sub encryptOutboundFile
{
	my ($this, $options) = @_;
	
	eval 
	{
		$this->{'attributes'}->{'gpg'}->import_keys( keys => qq|$options->{'workingBaseDirectory'}/encryption/perldev_pubkey.asc| );
	};
	
	## catch error from import call
	if ($@) 
	{
		$this->addErrors(qq|encrypt raised an exception: $@|);
	} 
	
	else
	{
		$options->{'encryptedOutboundFile'} = qq|$options->{'outboundFile'}.gpg|;
	
		## we need to eval because the gpg call croaks?! on an error
		## encrypt file for sending
		eval 
		{ 
			$this->{'attributes'}->{'gpg'}->encrypt
			(  
				plaintext   => $options->{'outboundFile'},  
				output      => $options->{'encryptedOutboundFile'},
				recipient 	=> $options->{'recipient'},
				passphrase  => $options->{'passPhrase'}, 
				armor       => 1,            
				sign   		=> 1,
			);
		};
		
		## catch error from encrypt call
		if ($@) 
		{
			$this->addErrors(qq|encrypt raised an exception: $@|);
		} 
	}
}

sub cleanupWorkingFiles
{
	my ($this, $options) = @_;
	
	##  remove the unencrypted input file
	$this->removeFile(	$options->{'tempDecryptedFile'} );
	
	## remove the unencrypted output file UNLESS debug is set
	if(!$this->{'attributes'}->{'debug'})
	{
		$this->removeFile(	$options->{'outboundFile'} );
	}	
}

sub openFileHandle
{
	my ($this, $options) = @_;
	
	$options->{'outboundFile'} = qq|$options->{'workingBaseDirectory'}/outbound/Test_Script_Output_$options->{'currentDate'}.csv|;
	
	$this->{'attributes'}->{'outputFileHandle'} = FileHandle->new("> $options->{'outboundFile'}");	
	
	return($this->{'attributes'}->{'outputFileHandle'});
}

sub closeFileHandle
{
	my ($this) = @_;
	
	undef $this->{'attributes'}->{'outputFileHandle'};
}

sub resetValidationError
{
	my ($this) = @_;
	
	undef $this->{'attributes'}->{'validationError'};
}

sub validationError
{
	my ($this, $error) = @_;
	
	if($error)
	{
		$this->{'attributes'}->{'validationError'} = $error;
	}
	
	return($this->{'attributes'}->{'validationError'});
}

sub recordIsValid
{
	my ($this, $record) = @_;
	
	my $status = 0;
	
	if( $this->emailIsValid($record) )
	{
		if( $this->phoneNumberIsValid($record) )
		{
			$status++;	
		}
	}
	
	return($status);	
}

sub emailIsValid
{
	my ($this, $record) = @_;
	
	my $status = 1;
	
	## check to make sure email is RFC compliant
	if(!valid($record->{'email'})) 
	{
		$status = 0;
	   	$this->validationError(qq[$record->{'email'}|not RFC compliant]);
	}	
	
	return($status);	
}

sub phoneNumberIsValid
{
	my ($this, $record) = @_;
	
	my $status = 0;
			
	my $characterClass = q|[^0-9]|;
	my $phoneRegEx 	   = qr/[0-9]{10}/;
		
	## strip out any non digits
	$record->{'phone'} =~ s/$characterClass//g;

	## make sure the phone number is 10 digits only
	if($record->{'phone'} =~ $phoneRegEx)
	{
		$status++;
	}
	
	else
	{
		$this->validationError(qq[$record->{'email'}|phone number is not 10 digits: $record->{'phone'}]);	
	}
	
	return($status);
}

sub parseXmlFile
{
	my ($this, $options) = @_;

	my $xmlData = [];
	
	my $xmlFile = $options->{'tempDecryptedFile'};

	my $xml = new XML::Simple;
	
	## this was added after looking at a discussion on perlmonks
	my $backend='XML::Parser';
	local $ENV{'XML_SIMPLE_PREFERRED_PARSER'} = $backend;
	
	## setup data structure from XML data
	$xmlData = $xml->XMLin($xmlFile, 'SuppressEmpty' => undef);
		
	$this->Debug('done parsing XML', $xmlData);
	
	return($xmlData);
}

sub removeFile
{
	my ($this, $file) = @_;
	
	unlink($file);
}

sub Output
{
	my ($this, $msg) = @_;
	
	print qq|$msg \n|;
}

sub Debug
{
	my ($this) = shift @_;
	
	my $msg;

	if($this->{'attributes'}->{'debug'})
	{		
		while ( my $debug = shift @_ )
		{
			if (ref($debug))
			{
			    $msg .= Dumper($debug);
			}
		
			elsif($debug)
			{
		    	$msg .= $debug;
			}
	
			$msg .= "\n";
		}

	   $msg .= "\n";
	
		print STDERR qq|$msg \n|;
	}
}

sub addErrors
{
	my ($this, $error) = @_;

	push(@{$this->{'attributes'}->{'errors'}}, $error);
}

sub getErrors
{
	my ($this) = @_;
	
	my $errors = [];

	if(
		$this->{'attributes'}->{'errors'}
		&& 
		ref($this->{'attributes'}->{'errors'}) eq "ARRAY"
		)
	{
		$errors = $this->{'attributes'}->{'errors'};
	}

	return($errors);
}

sub hasErrors
{
	my ($this) = @_;

	my $errorStatus = 0;

	if(
		$this->{'attributes'}->{'errors'}
		&&
		@{$this->{'attributes'}->{'errors'}}
	)
	{
		$errorStatus	= 1;
	}

	return($errorStatus);
}

sub dataBaseConnection
{
	my ($this) = @_;
	
	## TODO: put this in $ENV
	return( DBI->connect('DBI:mysql:test:localhost','root','qwerty') );	
}

sub insertRecord
{
	my ($this, $record) = @_;
	
	## this needs to be made more intelligent but it works for now
	my $dbh;
	#my $dbh = $this->dataBaseConnection();
	
	my $query = qq|
	insert ignore into User 
		(email, first_name, last_name, phone)
	value
		("$record->{'email'}", "$record->{'firstname'}", "$record->{'lastname'}", "$record->{'phone'}")|;
	
	$this->Debug('executing user query=', $query);
	
	my $id = 1;
	#my $id = $dbh->do($query);
	
	#if($dbh->errstr)
	if(1==2)
	{
		$this->addErrors($dbh->errstr);	
	}
	
	else
	{
		## add services
		foreach my $serviceID (@{$record->{'serviceIDs'}})
		{
			my $query = qq|
			insert ignore into UserOptions
				(emailID, serviceID)
			value
				($id, $serviceID)|;
		
			$this->Debug('executing services query=', $query);
		 	#$dbh->do($query);
		 
		 	#if($dbh->errstr)
		 	if(1==2)
			{
				$this->addErrors($dbh->errstr);	
			}
		}
	}
}

1;
