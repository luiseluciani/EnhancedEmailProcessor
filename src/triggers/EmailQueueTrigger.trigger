trigger EmailQueueTrigger on Email_Queue__c (after insert)
{
    List<Messaging.SingleEmailMessage> mailsToSend = new List<Messaging.SingleEmailMessage>();
    
    //Create a list of SingleEmailMessages to send out
    for(Email_Queue__c e : trigger.new)
    {
    	//Logic to determine whether we should send email resides in formula
        if(e.Can_Process__c)
        {
        	Messaging.SingleEmailMessage iMail = new Messaging.SingleEmailMessage();

        	if(!String.isBlank(e.ToAddresses__c))
        		iMail.setToAddresses(e.ToAddresses__c.split(';'));

        	if(!String.isBlank(e.CcAddresses__c))
        		iMail.setCCAddresses(e.CcAddresses__c.split(';'));

        	if(!String.isBlank(e.BccAddresses__c))
        		iMail.setBccAddresses(e.BccAddresses__c.split(';'));

        	if(!String.isBlank(e.Body_Plain_Text__c))
        		iMail.setPlainTextBody(e.Body_Plain_Text__c);

        	if(!String.isBlank(e.Body__c) && e.IsHTMLBody__c)
        		iMail.setHTMLBody(e.Body__c);

        	if(!String.isBlank(e.OrgWideEmailAddressId__c))
        		iMail.setOrgWideEmailAddressId(e.OrgWideEmailAddressId__c);
        	
        	if(!String.isBlank(e.Subject__c))
        		iMail.setSubject(e.Subject__c);

        	if(!String.isBlank(e.TargetObjectId__c))
        		iMail.setTargetObjectId(e.TargetObjectId__c);

			if(!String.isBlank(e.WhatObjectId__c))
        		iMail.setWhatId(e.WhatObjectId__c);

        	iMail.setTreatBodiesAsTemplate(true);

        	mailsToSend.add(iMail);
        }
    }


    if(!mailsToSend.isEmpty())
    {
    	Messaging.sendEmail(mailsToSend);
    }
}