## Small app to process PGP encrypted data

Q: How would we run this script from CRON (show an example)?  
A: via cron every 30 minutes  
*/30 * * * * perl /location/infoarmor.pl --debug --archive --etc..    

Q: If we wanted to take the output from this script and send an email to someemail@infoarmor.com how could that be accomplished?  
A: I would build a string with the output and use one one of the perl modules to send email to the user. This might also be helpful to alert them of code errors from the eval or scp.  

Q: If we wrap this script with a shell script (kick off from within a shell script), what would be the method to take action based on the scripts exit status?  
A: We would need to capture the output of "$?" then act accordingly.  

Q: If we wanted to loop through files in a directory and kick off this processing script on each how could that be accomplished?  
A: I would change the perl logic to loop through all files in the 'inbound' directory rather than have the 'file' passed via the command line.  
