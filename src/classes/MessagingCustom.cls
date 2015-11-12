public without sharing class MessagingCustom 
{
    private static string DEFAULT_FROM_EMAIL = UserInfo.getUserEmail();
      
    private static MessagingCustomEmailTemplateProcessor customTemplateProcessor;
    
    //Use this method to create refrence object to retrieve formatted templates using custom parser (no limits will be consumed)
    //Use GetEmailBody and GetIsHTML from the reference object to contruct single email messages body and do not set template id
    //Processing will be faster as message will be processed as plain text/html without processing templates for each single email
    //If activity needs to be created, explicity setCreateActivity to true when building the collection  
    //(useful if message content is same and not personalized by receipient)
    public static void ApplyTemplatesUsingCustomParser(SingleEmailMessage aSingleEmailMessage)
    {
        if(aSingleEmailMessage!=null)
        {
            MessagingCustomEmailTemplateProcessor lCustomEmailTemplateProcessor = new MessagingCustomEmailTemplateProcessor(new SingleEmailMessage[]{aSingleEmailMessage});
            lCustomEmailTemplateProcessor.FormatTemplate(aSingleEmailMessage);
        }
    }

    public static Map<Id,OrgWideEmailAddress> mapOrgWideEmails {get;set;}

    public static SendEmailResult[] SendEmail(List<MessagingCustom.SingleEmailMessage> lstSingleEmailMessages)
    {
        if(lstSingleEmailMessages==null)
        {
            throw new MessagingCustom.MessagingCustomException('Single Email Message Collection is null');
        }

        System.debug('MESSAGINGCUSTOM --Tying to send emails. Total of ' + lstSingleEmailMessages.Size());      

        //Getting information from the SingleEmailMessage
        if(mapOrgWideEmails == null)
            mapOrgWideEmails = new Map<Id,OrgWideEmailAddress>();

        Map<String, Set<Id>> mapTargetObjectIds = new Map<String, Set<Id>>();
        for(SingleEmailMessage emailMessage:lstSingleEmailMessages)
        {
            if(emailMessage.getTemplateId() != null && emailMessage.getTargetObjectId() != null)
            {
                string lObjectType = getObjectType(emailMessage.getTargetObjectId());
                if(!mapTargetObjectIds.containsKey(lObjectType))
                {
                    mapTargetObjectIds.put(lObjectType, new Set<Id>());
                }
                mapTargetObjectIds.get(lObjectType).add(emailMessage.getTargetObjectId());
            }

            if(!String.isBlank(emailMessage.getOrgWideEmailAddressId()))
            {
                mapOrgWideEmails.put(emailMessage.getOrgWideEmailAddressId(), null);
            }
        }
        
        //get org wide emails
        if(!mapOrgWideEmails.isEmpty())
        {
            mapOrgWideEmails = new Map<id,OrgWideEmailAddress>([select Id,Address, DisplayName from OrgWideEmailAddress where id=: mapOrgWideEmails.keySet()]);
        }
        
        //Get target object emails addresses and put them in a id > Email map
        Map<Id,string> mapTargetedEmails = new Map<Id,string> ();
        for(string objectName : mapTargetObjectIds.keySet())
        {
        	Set<id> lstTargetObjectIds = mapTargetObjectIds.get(objectName);
        	string queryStr = 'SELECT Id,Email FROM '+objectName+' WHERE id =:lstTargetObjectIds';
        	for(sObject obj : Database.query(queryStr))
        	{
        		mapTargetedEmails.put(obj.id, (string)obj.get('email'));
        	}
        }

        //Initialize the custom template processor. This is were we added a lot of our custom features
        String customParserInitializationError;
        try
        {
            customTemplateProcessor = new MessagingCustomEmailTemplateProcessor(lstSingleEmailMessages);
        }
        catch(Exception ex)
        {
            customParserInitializationError = ex.getTypeName() + '. ' + ex.getMessage() + ex.getStackTraceString();
        }
        
        //Start processing list of emails
        List<SingleEmailMessage> lstSingleEmailMessage = new List<SingleEmailMessage> ();
        List<Email_Queue__c> resultingEmails = new List<Email_Queue__c>();
        List<SendEmailResult> lstSendEmailResults = new List<SendEmailResult>(); 
        Integer iResultingEmails = 0;
        for(SingleEmailMessage emailMessage : lstSingleEmailMessages)
        {                
        	Email_Queue__c e = new Email_Queue__c();

            //Validations
            if(!String.isBlank(customParserInitializationError))
            {
                system.debug ('Error initializing Custom Template Parser: ' + customParserInitializationError );
                lstSendEmailResults.add(getEmailErrorResult('Error initializing Custom Template Parser.', emailMessage, StatusCode.INVALID_ID_FIELD));
                e.Status__c = 'Error';
                e.ErrorDescription__c = customParserInitializationError;
            }
            if(emailMessage.getTemplateId() != null && emailMessage.getTargetObjectId() != null && !mapTargetedEmails.containsKey(emailMessage.getTargetObjectId()))
            {
                System.debug('MESSAGINGCUSTOM --Receipients not found in the lead, contact or user object. Template id is not null');
                lstSendEmailResults.add(getEmailErrorResult('Receipients not found in the lead, contact or user object.', emailMessage, StatusCode.INVALID_EMAIL_ADDRESS ));
                e.Status__c = 'Error';
                e.ErrorDescription__c = 'Receipients not found in the lead, case or user object. StatusCode - INVALID_EMAIL_ADDRESS';
            }
            else if((emailMessage.getTemplateId() == null || emailMessage.getTargetObjectId() == null) && 
                emailMessage.getToAddresses() == null && emailMessage.getCcAddresses() == null && emailMessage.getBccAddresses() == null)
            {
            	System.debug('MESSAGINGCUSTOM --No Receipients Found. ');
                lstSendEmailResults.add(getEmailErrorResult('No receipients found. Either set to, cc and/or bcc address or template id is required.', emailMessage, StatusCode.INVALID_EMAIL_ADDRESS ));
                e.Status__c = 'Error';
                e.ErrorDescription__c = 'No receipients found. Either set to, cc and/or bcc address or template id is required. StatusCode - INVALID_EMAIL_ADDRESS';
            }

            //There needs to be a subject
            if(!String.isBlank(emailMessage.getSubject()) && emailMessage.getTemplateId() == null)
            {
                System.debug('MESSAGINGCUSTOM --Invalid Subject');
                lstSendEmailResults.add(getEmailErrorResult('Invalid Subject. Subject cannot be blank', emailMessage, StatusCode.REQUIRED_FIELD_MISSING));
                e.Status__c = 'Error';
                e.ErrorDescription__c = 'Invalid Subject. Subject cannot be blank. StatusCode - REQUIRED_FIELD_MISSING';
            }

            //If any errors are found, just continue to the next record.
            if(!String.isBlank(e.ErrorDescription__c))
            {
                e.FromAddress__c = 'dummy@ultimatesoftware.com.error';
                e.Subject__c = 'Error';
                resultingEmails.add(e);
                lstSingleEmailMessage.add(emailMessage);
                continue;
            }


            //if there is a templated, lets process it with our custom processor
            if(emailMessage.getTemplateId() != null)
            {
                System.debug('MESSAGINGCUSTOM --Processing Template Emails ');
                System.debug('MESSAGINGCUSTOM -- TEmplate Id ' + emailMessage.getTemplateId() + ', Target Object - ' + emailMessage.getTargetObjectId());
                
                try
                {
                	//Call custom parser to replace merge fields and add branding
                    customTemplateProcessor.FormatTemplate(emailMessage);
                }
                catch(Exception ex)
                {
                    system.debug ('Error applying templates: ' + ex.getTypeName() + '. ' + ex.getMessage() + ex.getStackTraceString());
                    lstSendEmailResults.add(getEmailErrorResult('Error Applying Templates.', emailMessage, StatusCode.INVALID_ID_FIELD));
                    e.Status__c = 'Error';
                    e.ErrorDescription__c = ex.getTypeName() + '. ' + ex.getMessage()+ + ex.getStackTraceString();
                }
                e.TemplateId__c = emailMessage.getTemplateId();
            }
            else
            {
            	System.debug('MESSAGINGCUSTOM -- NO TEMPLATE USED - Processing Emails ');                        
            }

            //If any errors are found, just continue to the next record.
            if(!String.isBlank(e.ErrorDescription__c))
            {
                system.debug('MESSAGINGCUSTOM --Messaging Custom New - Error found: '+e.ErrorDescription__c);
                e.FromAddress__c = 'dummy@ultimatesoftware.com.error';
                e.Subject__c = 'Error';
                resultingEmails.add(e);
                lstSingleEmailMessage.add(emailMessage);
                continue;
            }

            e.Subject__c = (String.isBlank(emailMessage.getSubject()))?'-No Subject-':emailMessage.getSubject();
            e.Body__c = emailMessage.getEmailBody();
            e.Body_Plain_Text__c = emailMessage.getPlainTextBody();
            e.IsHTMLBody__c = emailMessage.getIsHTMLEmail();
                
            System.debug('MESSAGINGCUSTOM -- Email Body ' + e.Body__c);
            
            if(emailMessage.getTargetObject() != null)
            {
                if(mapTargetedEmails.containsKey(emailMessage.getTargetObjectId()))
                {
                    e.ToAddresses__c = mapTargetedEmails.get(emailMessage.getTargetObjectId()) + ';' + (e.ToAddresses__c==null?'':e.ToAddresses__c);
                }
                e.TargetObjectId__c = emailMessage.getTargetObject().Id;
                e.TargetObjectName__c = emailMessage.getTargetObject().Type;
            }
                
            if(emailMessage.getWhatObject()!=null)
            {
                e.WhatObjectId__c = emailMessage.getWhatObject().Id;
                e.WhatObjectName__c = emailMessage.getWhatObject().Type; 
            }

            e.FromAddress__c = getFromAddress(emailMessage, mapOrgWideEmails);

            e.SaveAsActivity__c = emailMessage.getSaveAsActivity();
            e.OrgWideEmailAddressId__c = emailMessage.getOrgWideEmailAddressId();
            e.UseSenderDisplayName__c = emailMessage.getUseSenderDisplayName();
            e.SenderDisplayName__c = getDisplayName(emailMessage, mapOrgWideEmails); 


            //get lists of semi-colon separated email address strings containing up to 10000 characters.
            List<string> actRecipients = listToSemiColonSepListOfStrs(emailMessage.getToAddresses(), 10000);
            List<string> actCCRecipients = listToSemiColonSepListOfStrs(emailMessage.getCcAddresses(), 10000);
            List<string> actBCCRecipients = listToSemiColonSepListOfStrs(emailMessage.getBccAddresses(), 10000);


            if(actRecipients.size() > iResultingEmails)
                iResultingEmails = actRecipients.size();
            if(actCCRecipients.size() > iResultingEmails)
                iResultingEmails = actCCRecipients.size();
            if(actBCCRecipients.size() > iResultingEmails)
                iResultingEmails = actBCCRecipients.size();

            //Only if more than 10000 characters are used by to, cc or bcc addresses,iResultingEmails will be greater than 1 
            //Otherwise iResultingEmails will always be 1 and forloop will be executed only once
            for(Integer i = 0; i < iResultingEmails; i++)
            {
                Email_Queue__c temp = e.clone();
                
                if(actRecipients.size() > i)
                {
                    temp.ToAddresses__c = customTemplateProcessor.FormatAddressField(emailMessage, actRecipients[i]);
                    if(!emailMessage.getAllowSelfEmail() && !String.isBlank(e.ToAddresses__c))
                    {
                        e.ToAddresses__c = e.ToAddresses__c.replace(UserInfo.getUserEmail(),'');
                        if(!String.isBlank(e.ToAddresses__c))
                        {
                            e.ToAddresses__c = e.ToAddresses__c.replaceAll(';;','');
                        }
                    }
                }
                if(actCCRecipients.size() > i)
                {
                    temp.CcAddresses__c = customTemplateProcessor.FormatAddressField(emailMessage, actCCRecipients[i]);
                    if(!emailMessage.getAllowSelfEmail() && !String.isBlank(e.CcAddresses__c))
                    {
                        e.CcAddresses__c = e.CcAddresses__c.replace(UserInfo.getUserEmail(),'');
                        if(!String.isBlank(e.CcAddresses__c))
                        {
                            e.CcAddresses__c = e.CcAddresses__c.replaceAll(';;','');
                        }
                    }
                }
                if(actBCCRecipients.size() > i)
                {
                    temp.BccAddresses__c = customTemplateProcessor.FormatAddressField(emailMessage, actBCCRecipients[i]);
                    if(!emailMessage.getAllowSelfEmail() && !String.isBlank(e.BccAddresses__c))
                    {
                        e.BccAddresses__c = e.BccAddresses__c.replace(UserInfo.getUserEmail(),'');
                        if(!String.isBlank(e.BccAddresses__c))
                        {
                            e.BccAddresses__c = e.BccAddresses__c.replaceAll(';;','');
                        }
                    }
                }

                System.debug('MESSAGINGCUSTOM -- Adding email message to collection - ' + temp);
                resultingEmails.add(temp);
                lstSingleEmailMessage.add(emailMessage);
            }
        }


        System.debug('MESSAGINGCUSTOM -- Checking resultingEmails.size()>0 before insert ' + resultingEmails.size());
        System.debug('MESSAGINGCUSTOM -- Checking resultingEmails before insert ' + resultingEmails);
        
        if(!resultingEmails.isEmpty())
        {
            try
            {
                System.debug('MESSAGINGCUSTOM -- inserting email messages to the queue ');
                insert resultingEmails;
                System.debug('MESSAGINGCUSTOM -- calling add attachments ');
                addAttachments(lstSingleEmailMessage, resultingEmails);
                
                for(Email_Queue__c emailQueue : resultingEmails)
                {
                    System.debug('MESSAGINGCUSTOM -- adding Email Result for Email Queue: '+emailQueue);
                    SendEmailResult oSendEmailResult = new SendEmailResult();
                    oSendEmailResult.setIsSuccess(true);
                    oSendEmailResult.setEmailQueue(emailQueue);
                    lstSendEmailResults.add(oSendEmailResult);
                }
            }
            catch(DMLException ex)
            {
                for(Email_Queue__c emailQueue : resultingEmails)
                {
                    SendEmailResult oSendEmailResult = new SendEmailResult();
                    oSendEmailResult.setIsSuccess(false);
                    system.debug('MESSAGINGCUSTOM --Messaging Custom New - Error found: '+ex.getMessage());
                    oSendEmailResult.addError(new SendEmailError(ex.getMessage()));
                    lstSendEmailResults.add(oSendEmailResult);
                }
            }
        }
        return lstSendEmailResults;
    }
    
    public static string getObjectType(Id recordId)
    {
        return String.valueOf(recordId.getSObjectType()); 
    }
    
    private static string getFromAddress(SingleEmailMessage message, map<id, OrgWideEmailAddress> orgWideEmailsMap)
    {
        string fromAddress = '';
        if(!String.isBlank(message.getFromAddress()))
        {
            fromAddress = message.getFromAddress();
            
        }
        else if(message.getOrgWideEmailAddressId() != null && orgWideEmailsMap.containsKey(message.getOrgWideEmailAddressId()))
        {
            fromAddress = orgWideEmailsMap.get(message.getOrgWideEmailAddressId()).Address;
        } 
        else
        {
            fromAddress = (DEFAULT_FROM_EMAIL != null)?DEFAULT_FROM_EMAIL:'donotreply.custsupport@ultimatesoftware.com';
        }
        return fromAddress;
    }
    
    private static string getDisplayName(SingleEmailMessage message, map<id, OrgWideEmailAddress> orgWideEmailsMap)
    {
        string displayName = '';
        if(message.getUseSenderDisplayName() && !String.isBlank(message.getSenderDisplayName()))
        {
            displayName = message.getSenderDisplayName();
        }
        else if(message.getOrgWideEmailAddressId() != null && orgWideEmailsMap.containsKey(message.getOrgWideEmailAddressId()))
        {
            displayName = orgWideEmailsMap.get(message.getOrgWideEmailAddressId()).DisplayName;
        }
        
        return displayName;
    }
    
    private static void addAttachments(List<SingleEmailMessage> lstSingleEmailMessage, List<Email_Queue__c> lstEmailQueue)
    {
        if(lstSingleEmailMessage==null)
        	return;
        List<Attachment> attachmentsToInsert = new List<Attachment>();
        for(integer i = 0 ; i < lstSingleEmailMessage.size(); i++)
        {
            SingleEmailMessage emailMessage = lstSingleEmailMessage[i];

            if(emailMessage !=null && emailMessage.getFileAttachments() !=null && emailMessage.getFileAttachments().size() > 0)
            {
				Email_Queue__c emailQueue =  lstEmailQueue[i];
                //If there are any errors on the emailqueue, don't even bother
                if(String.isBlank(emailQueue.ErrorDescription__c))
                {
    				if(emailQueue.Id != null)
    				{
    					for(EmailFileAttachment emailAttachment : emailMessage.getFileAttachments())
    					{
    					    Attachment att = new Attachment();
    					    att.Body = emailAttachment.getBody();
    					    att.ParentId = emailQueue.id;
    					    att.name = emailAttachment.getFileName();
    					    att.ContentType = emailAttachment.getContentType();
    					    attachmentsToInsert.add(att);
    					}
    				}
                }
            }
            
        }
        if(attachmentsToInsert!=null && attachmentsToInsert.size()>0)
        {
            System.debug('MESSAGINGCUSTOM -- attachmentsToInsert = ' + attachmentsToInsert.size());
            insert attachmentsToInsert;
        }
    }
    
    //This method converts a list of strings into a list of Semi-colon separated strings. It breaks the string apart
    //once it reaches a certain length
    private static List<string> listToSemiColonSepListOfStrs(List<string> strList, Integer maxStrLength)
    {
        List<string> SemiColonSepListOfStrs = new List<string>();
        
        if(strList != null)
        {
            string semiColonSepStr = '';
            for(String item : strList)
            {
                if(semiColonSepStr.Length()+item.Length()+1 > maxStrLength)
                {
                    SemiColonSepListOfStrs.add(semiColonSepStr);
                    semiColonSepStr = '';
                }
                semiColonSepStr = semiColonSepStr + item + ';';
            }

            if(semiColonSepStr.Length() > 0)
            {
                SemiColonSepListOfStrs.add(semiColonSepStr);
            }
        }
        
        return SemiColonSepListOfStrs;
    }
    
    private static SendEmailResult getEmailErrorResult(string message, SingleEmailMessage emailMessage)
    {
        return getEmailErrorResult(message, emailMessage, null);
    }
    private static SendEmailResult getEmailErrorResult(string message, SingleEmailMessage emailMessage, Statuscode aStatusCode)
    {
        SendEmailResult oSendEmailResult = new SendEmailResult();
        oSendEmailResult.setIsSuccess(false);
        
        oSendEmailResult.addError(new SendEmailError(message, aStatusCode, emailMessage));
        return oSendEmailResult;
    }
    
    public class SingleEmailMessage
    {
        private string m_sFromAddress;
        private List<String> lstToAddresses;
        private List<string> lstCcAddresses;
        private List<string> lstBccAddresses;
        private string m_sSubject;
        private string m_sBody;
        private string m_sPlainTextBody;
        private string m_sHTMLTextBody;
        private Boolean m_bIsHTML = false;
        private string m_sReplyToAddress;
        private string m_sImportance;
        private string m_sSensitivity;
        private string m_sSenderDisplayName;
        private List<EmailFileAttachment> lstFileAttachments = new List<EmailFileAttachment>();
        private RelatedObject m_oTargetObject;
        private RelatedObject m_oWhatObject;
        private Id m_sTemplateId;
        
        private string m_sOrgWideEmailAddressId; 
        private boolean m_bUseSenderDisplayName=false;
        private boolean m_bSaveAsActivity=true;
        private boolean m_bUseSignature=true;
        private boolean m_bUseCustomParser=false;
        private string m_sCustomBrandingTemplateName='DEFAULT LETTER';
        private boolean m_allowSelfEmail = true;

        public void setOrgWideEmailAddressId    (String anOrgWideEmailAddressId)
        {
            m_sOrgWideEmailAddressId = anOrgWideEmailAddressId;
        }
        
        public String getOrgWideEmailAddressId()
        {
            return m_sOrgWideEmailAddressId;
        }
        //Required
        public void setSenderDisplayName(string aSenderDisplayName)
        {
            m_bUseSenderDisplayName = true;
            m_sSenderDisplayName = aSenderDisplayName;
        }
        
        public string getSenderDisplayName()
        {
            return m_sSenderDisplayName;
        }
        
        public boolean getUseSenderDisplayName()
        {
            return m_bUseSenderDisplayName;
        }
        
        public void setFromAddress  (String anEmailAddress)
        {
            m_sFromAddress = anEmailAddress;
        }
        
        public String getFromAddress()
        {
            return m_sFromAddress;
        }
            
        //List of to addresses
        public void setToAddresses  (String[] arrEmailAddresses)
        {
            if(arrEmailAddresses!=null && arrEmailAddresses.Size()>0)
                lstToAddresses = arrEmailAddresses;
        }
        
        public List<String> getToAddresses()
        {
            return lstToAddresses;
        }
        //Optional. A list of blind carbon copy (BCC) addresses. The maximum allowed is 25. This argument is allowed only when a template is not used. At least one value must be specified in one of the following fields: toAddresses, ccAddresses, bccAddresses, targetObjectId, or targetObjectIds.
        public void setBccAddresses (String[] arrEmailAddresses)
        {
            if(arrEmailAddresses!=null && arrEmailAddresses.Size()>0)
                lstBccAddresses = arrEmailAddresses;
        }
        
        public List<String> getBccAddresses()
        {
            return lstBccAddresses;
        }
        //Optional. A list of carbon copy (CC) addresses. The maximum allowed is 25. This argument is allowed only when a template is not used.
        public void setCcAddresses  (String[] arrEmailAddresses)
        {
            if(arrEmailAddresses!=null && arrEmailAddresses.Size()>0)
                lstCcAddresses = arrEmailAddresses;     }
        
        public List<String> getCcAddresses()
        {
            return lstCcAddresses;
        }
        /*
        All email must have a recipient value of at least one of the following:
        toAddresses
        ccAddresses
        bccAddresses
        targetObjectId
        targetObjectIds
        setCharset  String  Void    Optional. The character set for the email. If this value is null, the user's default value is used.
        setDocumentAttachments  ID[]    Void    Optional. A list containing the ID of each document object you want to attach to the email. You can attach multiple documents as long as the total size of all attachments does not exceed 10 MB.
        */
        //. A list containing the file names of the binary and text files you want to attach to the email. You can attach multiple files as long as the total size of all attachments does not exceed 10 MB.
        
        
        public void setFileAttachments  (Messaging.EmailFileAttachment[]  emailFileAttachments)
        {
            if(emailFileAttachments!=null && emailFileAttachments.size()>0)
            {
                System.debug('MESSAGINGCUSTOM --Setting File Attachments From Salesforce SingleEmailMessage Attachment');
                for(Messaging.EmailFileAttachment emailAttachment:emailFileAttachments)
                {
                    lstFileAttachments.add(new MessagingCustom.EmailFileAttachment(emailAttachment));
                }
            }
        }
        public void setFileAttachments  (EmailFileAttachment[]  emailFileAttachments)
        {
            if(emailFileAttachments!=null && emailFileAttachments.size()>0)
            {
                lstFileAttachments.addAll(emailFileAttachments);
            }
        }
        
        public List<EmailFileAttachment> getFileAttachments()
        {
            return lstFileAttachments;
        }
        
        //The HTML version of the email, specified by the sender. The value is encoded according to the specification associated with the organization. You must specify a value for setTemplateId, setHtmlBody, or setPlainTextBody. Or, you can define both setHtmlBody and setPlainTextBody.
        public void setHtmlBody (String aHTMLBody)
        {
            m_sHTMLTextBody = aHTMLBody;
            m_bIsHTML = true;
        }
        
        //The text version of the email, specified by the sender. You must specify a value for setTemplateId, setHtmlBody, or setPlainTextBody. Or, you can define both setHtmlBody and setPlainTextBody.
        
        public void setPlainTextBody(String aTextBody)
        {
            m_sPlainTextBody = aTextBody;
        }
        
        public boolean getIsHTMLEmail()
        {
            return m_bIsHTML;
        }
        
        public String getEmailBody()
        {
            if(m_bIsHTML) {
                return m_sHTMLTextBody;
            }
            else 
            {
                return m_sPlainTextBody;
            }
        }

        public String getPlainTextBody()
        {
            return m_sPlainTextBody;
        }
        public String getHTMLBody()
        {
            return m_sHTMLTextBody;
        }   
        //The In-Reply-To field of the outgoing email. Identifies the email or emails to which this one is a reply (parent emails). Contains the parent email or emails' message-IDs.
        public void setInReplyTo(String aReplyToEmailAddress)
        {
            m_sReplyToAddress = aReplyToEmailAddress;
        }
        
        public String getInReplyTo()
        {
            return m_sReplyToAddress;
        }
        //The email subject line. If you are using an email template, the subject line of the template overrides this value.
        public void setSubject(String aSubject)
        {
            m_sSubject = aSubject;
        }
        
        public String getSubject()
        {
            return m_sSubject;
        }
        
        public void setTemplateId(Id aTemplateId)
        {
            m_sTemplateId = aTemplateId;
        }
        
        public Id getTemplateId()
        {
            return m_sTemplateId;
        }
        
        private RelatedObject getTargetObject()
        {
            return m_oTargetObject;
        }
        
        public Id getTargetObjectId()
        {
            return m_oTargetObject!=null?m_oTargetObject.Id:null;
        }
        
        public void setTargetObjectId(Id aTargetObjectId)
        {
            m_oTargetObject = new RelatedObject(aTargetObjectId, getObjectType(aTargetObjectId));
        }
        
        private RelatedObject getWhatObject()
        {
            return m_oWhatObject;
        }
        
        public Id getWhatId()
        {
            return m_oWhatObject!=null?m_oWhatObject.Id:null;
        }
        
        public void setWhatId(Id aWhatObjectId)
        {
            m_oWhatObject = new RelatedObject(aWhatObjectId, MessagingCustom.getObjectType(aWhatObjectId));
        }
        
        public void setSaveAsActivity   (boolean bSaveAsActivity)
        {
            m_bSaveAsActivity = bSaveAsActivity;
        }
      
        public boolean getSaveAsActivity()
        {
            return m_bSaveAsActivity;
        }
        
        private boolean getUseSignature()
        {
            return m_bUseSignature;
        }
        
        public void setUseSignature   (boolean bUseSignature)
        {
            m_bUseSignature = bUseSignature;
        }

        public void setAllowSelfEmail(Boolean allowSelfEmail)
        {
            m_allowSelfEmail = allowSelfEmail;
        }
    
        public Boolean getAllowSelfEmail()
        {
            return m_allowSelfEmail;
        }
        
        //setOrgWideEmailAddressId  ID  Void    Optional. The ID of the organization-wide email address associated with the outgoing email. The object's DisplayName field cannot be set if the setSenderDisplayName field is already set.
        //setReferences String  Void    Optional. The References field of the outgoing email. Identifies an email thread. Contains the parent emails' References and message IDs, and possibly the In-Reply-To fields.
    }

    public class EmailFileAttachment{
        private blob m_blAttachment;
        private string m_sContentType;
        private string m_sFileName;
        private boolean m_sContentDisposition;

        public EmailFileAttachment() {}
    
        public EmailFileAttachment(Attachment att)
        {
            m_blAttachment = att.Body;
            m_sContentType = att.ContentType;
            m_sFileName = att.name;
        }

        public EmailFileAttachment(Messaging.EmailFileAttachment att)
        {
            m_blAttachment = att.getBody();
            m_sContentType = att.getContentType();
            m_sFileName = att.getFileName();
        }
        
        public void setBody(blob attachment)
        {
            m_blAttachment = attachment;
        }
        
        public void setContentType(String aContentType)
        { 
            m_sContentType = aContentType;
        }
        
        public void setFileName(String aFileName)
        { 
            m_sFileName = aFileName;
        }
        
        public void setInline(Boolean bContentDisposition)
        { 
            m_sContentDisposition = bContentDisposition;
        }
        
        public blob getBody()
        {
            return m_blAttachment;
        }
        
        public string getContentType()
        { 
            return m_sContentType;
        }
        
        public string getFileName()
        { 
            return m_sFileName;
        }
        
        public boolean getContentDisposition()
        { 
            return m_sContentDisposition;
        }
    
    }
    
    public class RelatedObject
    {
        public Id Id{get;set;}
        public string Type{get;set;}
        //public RelatedObject()
        {}
        public RelatedObject(Id aId, string aType)
        {
            Id = aId;
            Type = aType; 
        }
    }
    
    public class SendEmailResult
    {
        private boolean m_bIsSuccess = false;
        private Email_Queue__c m_oEmailQueue;
        
        private SendEmailError[] m_lstSendEmailErrors;
        private void setIsSuccess(boolean aValue)
        {
            m_bIsSuccess = aValue;
        }
        public boolean IsSuccess()
        {
            return m_bIsSuccess;
        }
        
        private void setEmailQueue(Email_Queue__c aEmailQueue)
        {
            m_oEmailQueue = aEmailQueue;
        }
        public Email_Queue__c getEmailQueue()
        {
            return m_oEmailQueue;
        }
        
        private void addError(SendEmailError anError)
        {
            if(m_lstSendEmailErrors==null) m_lstSendEmailErrors = new List<SendEmailError>();
            m_lstSendEmailErrors.add(anError);
        }
        
        public SendEmailError[] getErrors()
        {
            return m_lstSendEmailErrors;
        } 
        
        
    }
    
    public class SendEmailError{
        
        public string Message {get;set;}
        public Statuscode StatusCode {get;set;}
        public SingleEmailMessage EmailMessage {get;set;}

        public SendEmailError(string m)
        {
        	Message = m;
        }

        public SendEmailError(string m, Statuscode sc, SingleEmailMessage msg)
        {
        	Message = m;
        	StatusCode = sc;
        	EmailMessage = msg;
        }

    }
    
    public class MessagingCustomException extends Exception{
    }
}