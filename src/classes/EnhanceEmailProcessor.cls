global with sharing class EnhancedEmailProcessor 
{
	global class SendParameters 
	{
        @InvocableVariable(required=true label='Record Id')
        global String RecordId;

        @InvocableVariable(required=true label='Enhanced Email Action Id')
        global String EnhancedEmailActionId;
    }

	/**
     * Send percentages and durations to LittleBits cloud enabled devices
     **/
    @InvocableMethod(
        Label='Send email using extended template'
        Description='Sends an email using an extended template that leverages related objects')
    global static void send(List<SendParameters> params)
    {
    	processEnhancedEmailActions(params);
	}

	public static void processEnhancedEmailActions(List<SendParameters> params)
	{
		try
		{
			processEnhancedEmailActions_Internal(params);
		}
		catch(Exception ex)
		{
			throw new EmailException(ex);
		}
	}

	private static void processEnhancedEmailActions_Internal(List<SendParameters> params)
	{
		if(params.isEmpty())
    		return;

        //get set of Enhance email Action Ids
        Set<Id> enhancedEmailActionIdSet = new Set<Id>();
        for(SendParameters p : params)
        {
        	enhancedEmailActionIdSet.add(p.EnhancedEmailActionId);
        }

        //Get the affected Enhanced Email Actions
        Map<id,Enhanced_Email_Action__mdt> eeaMap = new Map<id,Enhanced_Email_Action__mdt>([SELECT Allow_Self_Emails__c,
        																						   Enhanced_Email_Template__c, 
                                                                                                   Recipient_List__c, From_Email_Address__c
                                                                                            FROM Enhanced_Email_Action__mdt 
                                                                                            WHERE id IN :enhancedEmailActionIdSet]);
        Map<string, Id> emailTemplatesMap = new Map<string, Id>();
        if(!eeaMap.isEmpty())
        {
        	List<string> emailTemplateNames =  new List<string>();
        	for(Enhanced_Email_Action__mdt eea : eeaMap.values())
        	{
        		emailTemplateNames.add(eea.Enhanced_Email_Template__c);
    		}
        	system.debug('Email Template Names: '+emailTemplateNames);
        	for(EmailTemplate et :[SELECT id, DeveloperName FROM EmailTemplate WHERE DeveloperName IN :emailTemplateNames])
        	{
        		emailTemplatesMap.put(et.DeveloperName, et.id);
        	}
        }
        
        List<MessagingCustom.SingleEmailMessage> lstmail = new List<MessagingCustom.SingleEmailMessage> ();
        //Get the list of all records, templates, and recipients
        for(SendParameters p : params)
        {
        	if(!eeaMap.containsKey(p.EnhancedEmailActionId))
        		continue;

        	String emailTemplateId = emailTemplatesMap.get(eeaMap.get(p.EnhancedEmailActionId).Enhanced_Email_Template__c);
        	String recipients = eeaMap.get(p.EnhancedEmailActionId).Recipient_List__c;
        	Boolean allowSelfEmail = eeaMap.get(p.EnhancedEmailActionId).Allow_Self_Emails__c;
            String fromAddress = eeaMap.get(p.EnhancedEmailActionId).From_Email_Address__c;

            MessagingCustom.SingleEmailMessage mail = new MessagingCustom.SingleEmailMessage();
        	mail.setToAddresses(recipients.split(','));
        	mail.setTemplateId(emailTemplateId);
        	mail.setWhatId(p.RecordId);
        	mail.setAllowSelfEmail(allowSelfEmail);
        	
        	if(!String.isBlank(fromAddress))
            {
                mail.setFromAddress(fromAddress);
            }
	        lstmail.add(mail);
        }

        //Use custom email solution to send email messages
        MessagingCustom.sendEmail( lstmail);
    }
}