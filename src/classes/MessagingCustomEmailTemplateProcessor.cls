public without sharing class MessagingCustomEmailTemplateProcessor {

    public static List<MessagingCustom.SingleEmailMessage> m_lstSingleEmailMessages;
    public static Map<Id, EmailTemplate> mapEmailTemplates = new Map<Id, EmailTemplate>();
    public static Map<string, Set<Id>> mapSObjectIds = new Map<string, Set<Id>>();    
    public static Map<string, Map<Id,sObject>> mapSObjectRecords = new Map<string, Map<Id,sObject>>();
    public static Map<Id,List<MessagingCustom.EmailFileAttachment>> mapEmailTemplateFileAttachments = new Map<Id,List<MessagingCustom.EmailFileAttachment>>();
    public static Map<Id,List<MessagingCustom.EmailFileAttachment>> mapEmailTemplateAttachments {get;set;}
    public static Map<string,Map<string,string>> mergeTextToValueMapPerRecord = new Map<string,Map<string,string>>();
    public static Set<String> brandTemplateIds = new Set<String>();
    public static Map<id,Brand_Template_Cache__c> cachedBrandTemplatesMap = new Map<id,Brand_Template_Cache__c>();
    public static Map<string,Map<string, Schema.DescribeFieldResult>> cache_getObjectFieldDescribeResults {get;set;}
    public static Map<String, Schema.SObjectType> globalDescribe {get;set;}
    public static final string customSettingIdentifier = 'setup_';
    public static final string DateTimeFormat = 'MM/dd/yyyy hh:mm a z';
    
    
    public MessagingCustomEmailTemplateProcessor(List<MessagingCustom.SingleEmailMessage> lstSingleEmailMessages)
    {
        m_lstSingleEmailMessages = lstSingleEmailMessages;
        Initialize();
    }


    public string FormatAddressField(MessagingCustom.SingleEmailMessage aSingleEmailMessage, string semiColonSepAddresses)
    {
        string before = semiColonSepAddresses = semiColonSepAddresses;
        for(string recordId : new List<string> { aSingleEmailMessage.getWhatId(), aSingleEmailMessage.getTargetObjectId(), UserInfo.getUserId(), 'setup'})
        {
            if(recordId == null || !mergeTextToValueMapPerRecord.containsKey(recordId))
                continue;

            semiColonSepAddresses = getFormattedMessage(semiColonSepAddresses,recordId);
        }

        semiColonSepAddresses = semiColonSepAddresses.replaceAll(',',';');
        system.debug('MESSAGINGCUSTOM TEMPLATE PROC -- Formatting addresses. Input: '+before+', output: '+semiColonSepAddresses);
        return semiColonSepAddresses;
    }
    
    // Call this method to custom parse templates and update subject, plaintextbody and html body
    public void FormatTemplate(MessagingCustom.SingleEmailMessage aSingleEmailMessage)
    {
        if(aSingleEmailMessage != null && aSingleEmailMessage.getTemplateId() != null)
        {
            if(mapEmailTemplates.containsKey(aSingleEmailMessage.getTemplateId()))
            {
                EmailTemplate et = mapEmailTemplates.get(aSingleEmailMessage.getTemplateId());
                string strBody = et.Body;
                string strHtmlValue = et.HtmlValue;
                string strSubject = et.Subject;

                for(string recordId : new List<string> { aSingleEmailMessage.getWhatId(), aSingleEmailMessage.getTargetObjectId(), UserInfo.getUserId(), 'setup'})
                {
                    if(recordId == null || !mergeTextToValueMapPerRecord.containsKey(recordId))
                        continue;

                    strBody = getFormattedMessage(strBody,recordId);
                    if(et.TemplateType != 'text')
                    {
                        strHtmlValue = getFormattedMessage(strHtmlValue,recordId);
                    }
                    strSubject = getFormattedMessage(strSubject,recordId);
                }

                system.debug('MESSAGINGCUSTOM TEMPLATE PROC -- strSubject in Custom Parser: ' + strSubject);
                aSingleEmailMessage.setSubject(strSubject);

                aSingleEmailMessage.SetPlainTextBody(strBody);
                if(et.TemplateType != 'text' && !String.isEmpty(strHtmlValue))
                {
                    strHtmlValue = strHtmlValue.replace('<![CDATA[','');
                    strHtmlValue = strHtmlValue.replace(']]>','');
                    if(et.BrandTemplateId != null)
                    {
                        if(cachedBrandTemplatesMap.containsKey(et.BrandTemplateId))
                        {
                            strHtmlValue = cachedBrandTemplatesMap.get(et.BrandTemplateId).HTML__c.replace('[[BODYPLACEHOLDER]]',strHtmlValue);
                        }
                    }
                    strHtmlValue = strHtmlValue.replace('<![CDATA[','').replace(']]>','');
                    aSingleEmailMessage.setHTMLBody(strHtmlValue);
                }
                
                if (mapEmailTemplateFileAttachments.containsKey(aSingleEmailMessage.getTemplateId()))
                {
                    aSingleEmailMessage.setFileAttachments(mapEmailTemplateFileAttachments.get(aSingleEmailMessage.getTemplateId()));
                }
            }
            
        }
    }
    
    
    private void Initialize()
    {
        if(m_lstSingleEmailMessages != null && !m_lstSingleEmailMessages.isEmpty())
        {
            Set<Id> templateIds = new Set<Id>();
            Map<string, Map<String, String>> mapSObjectQueryFields = new Map<string, Map<String, String>>(); 
            // get all template ids, target object ids and what ids from the email message 
            for(MessagingCustom.SingleEmailMessage m : m_lstSingleEmailMessages)
            {
                if(m.getTemplateId() != null)
                {
                    templateIds.add(m.getTemplateId());
                }
                
                if(m.getWhatId() != null)
                {
                    addIdToSObjectMap(m.getWhatId());
                }
                
                if(m.getTargetObjectId() != null)
                {
                    addIdToSObjectMap(m.getTargetObjectId());
                }

                //Search the address fields to see if there are any merge fields in there.
                string textToSearchForMergeFields = '';
                if(m.getFromAddress() != null)
                    textToSearchForMergeFields+=m.getFromAddress();
                if(m.getToAddresses() != null)
                    textToSearchForMergeFields+=m.getToAddresses();
                if(m.getCcAddresses() != null)
                    textToSearchForMergeFields+=m.getCcAddresses();
                if(m.getBccAddresses() != null)
                    textToSearchForMergeFields+=m.getBccAddresses();

                extractTemplateFields(textToSearchForMergeFields, mapSObjectQueryFields);
            }
            
            if(templateIds != null && !templateIds.isEmpty())
            {
                //get all templates
                mapEmailTemplates = new Map<Id, EmailTemplate>([SELECT Id,Body,BrandTemplateId,HtmlValue,Name,Subject,TemplateType,LastModifiedDate
                                                                FROM EmailTemplate Where Id=:templateIds]);

                for(EmailTemplate et : mapEmailTemplates.values())
                {
                    if(et.BrandTemplateId != null)
                        brandTemplateIds.add(et.BrandTemplateId);
                }

                //get all custom branding templates
                if(!brandTemplateIds.isEmpty())
                {
                    //Get all cached BrandTemplates
                    for(Brand_Template_Cache__c btc : [SELECT id, HTML__c, Brand_Template_Id__c, LastModifiedDate 
                                                       FROM Brand_Template_Cache__c 
                                                       WHERE Brand_Template_Id__c IN :brandTemplateIds])
                    {
                        cachedBrandTemplatesMap.put(btc.Brand_Template_Id__c, btc);
                    }
                }
                
                //build sObject and Fields used in template
                //Extract all merge texts from the templates
                //Also prepare to get new brand templates
                Map<id, Messaging.SingleEmailMessage> templateIdToMailMap = new Map<id,Messaging.SingleEmailMessage>();
                for(EmailTemplate et : mapEmailTemplates.values())
                {
                    string textToSearchForMergeFields = et.body+et.subject+et.HtmlValue;
                    extractTemplateFields(textToSearchForMergeFields, mapSObjectQueryFields);

                    if(et.BrandTemplateId != null && 
                        (!cachedBrandTemplatesMap.containsKey(et.BrandTemplateId) || (cachedBrandTemplatesMap.get(et.BrandTemplateId).LastModifiedDate != null && et.LastModifiedDate > cachedBrandTemplatesMap.get(et.BrandTemplateId).LastModifiedDate)))
                    {
                        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                        mail.setToAddresses(new String[]{'invalid@emailaddr.es'});
                        mail.setTargetObjectId(UserInfo.getUserId());
                        mail.setSaveAsActivity(false);
                        mail.setTemplateId(et.Id);
                        templateIdToMailMap.put(et.Id, mail);
                        if(!cachedBrandTemplatesMap.containsKey(et.BrandTemplateId))
                            cachedBrandTemplatesMap.put(et.BrandTemplateId, new Brand_Template_Cache__c(Brand_Template_Id__c = et.BrandTemplateId, HTML__c = ''));
                    }
                }

                //if there are any brand templates that need caching, lets cache them now
                if(templateIdToMailMap.size() > 0)
                {
                    system.debug('MESSAGINGCUSTOM TEMPLATE PROC -- Fake sending the following emails: '+templateIdToMailMap);
                    Savepoint sp = Database.setSavepoint();
                    Messaging.sendEmail(templateIdToMailMap.values());
                    Database.rollback(sp);

                    List<Brand_Template_Cache__c> brandTemplateCache_ToUpsert = new List<Brand_Template_Cache__c>();
                    for(Id tId : templateIdToMailMap.keySet())
                    {
                        string emailHTML = templateIdToMailMap.get(tId).getHTMLBody();
                        Brand_Template_Cache__c temp = cachedBrandTemplatesMap.get(mapEmailTemplates.get(tId).BrandTemplateId);

                        //Use the format of the templates to determine what part is actually coming from the Brand Temmplate vs Email Template
                        Integer startBody = emailHTML.indexOf('<td styleInsert="1"');
                        startBody = emailHTML.indexOf('<table', startBody);
                        Integer endBody = emailHTML.indexOf('</table>', startBody)+8;
                        string htmlBody = emailHTML.substring(startBody, endBody);
                        
                        temp.HTML__c = emailHTML.replace(htmlBody,'[[BODYPLACEHOLDER]]');
                        brandTemplateCache_ToUpsert.add(temp);
                    }

                    //add the new Brand Templates to our custom object to cache them, then add the new ones to our local variable for usage            
                    if(brandTemplateCache_ToUpsert.size() > 0)
                    {
                        upsert brandTemplateCache_ToUpsert;

                        for(Brand_Template_Cache__c btc : brandTemplateCache_ToUpsert)
                            cachedBrandTemplatesMap.put(btc.Brand_Template_Id__c, btc);
                    }
                }

                
                //Extracting any file attachements that are included as part of the template
                getEmailTemplateAttachmentMap(templateIds);
                        
                
                //Create dynamic SOQL based on list of merge fields
                for (string objectType : mapSObjectQueryFields.keySet())
                {
                    String queryStr = 'Select ';
                    string lDelimeter = '';
                    Set<String> mergeTexts = new Set<string>();
                    Boolean isCustomSetting = objectType.startsWith(customSettingIdentifier);
                    mergeTexts.addAll(mapSObjectQueryFields.get(objectType).values());

                    string fieldsStr = String.Join(new List<string>(mergeTexts),',');
                    fieldsStr = fieldsStr.toLowerCase().replace(',link,',',');
                    //If the object type starts with a "setup_" (customSettingIdentifier), then this is a custom setting.
                    if(isCustomSetting && !fieldsStr.contains('setupownerid'))
                    {
                        fieldsStr+=',setupownerid';
                        objectType = objectType.replace(customSettingIdentifier,'');
                    }

                    queryStr = 'SELECT ' + fieldsStr + ' FROM ' + objectType;

                    //check we have a corresponding query for the ids
                    Set<Id> lstIds = new Set<Id>();
                    string userId = UserInfo.getUserId();
                    string profileId = UserInfo.getProfileId();
                    string orgId = UserInfo.getOrganizationId();
                    string userRoleId = UserInfo.getUserRoleId();
                    if (objectType.equalsIgnoreCase('user'))
                    {
                        queryStr = queryStr + ' where id =:userId ';
                    }
                    else if (objectType.equalsIgnoreCase('profile'))
                    {
                        queryStr = queryStr + ' where id =:profileId ';
                    }
                    else if (objectType.equalsIgnoreCase('userrole'))
                    {
                        queryStr = queryStr + ' where id =:userRoleId ';
                    }
                    else if (objectType.equalsIgnoreCase('organization'))
                    {
                        queryStr = queryStr + ' where id =:orgId ';
                    }
                    else if(isCustomSetting) //Custom Setting
                    {
                        queryStr = queryStr + ' where SetupOwnerId IN (:userId, :profileId, :orgId) ';   
                    }
                    else
                    {
                        lstIds = mapSObjectIds.get(objectType);
                        queryStr = queryStr + ' where id in :lstIds';
                    }

                    //execute query for all merge fields and load it to sObject map 
                    System.debug('MESSAGINGCUSTOM TEMPLATE PROC -- Query to execute = ' + queryStr);
                    System.debug('MESSAGINGCUSTOM TEMPLATE PROC -- lstIds = ' + lstIds);
                    if(!String.IsBlank(queryStr))
                    { 
                        Map<Id, sObject> mapSObjects = new Map<Id, sObject>(Database.query(queryStr));
                        System.debug('MESSAGINGCUSTOM TEMPLATE PROC -- Record retrived for ' + objectType + ', total: ' + mapSObjects.size());
                        if(mapSObjects != null && !mapSObjects.isEmpty())
                        {
                            /*
                            Custom settings in merge fields are always Hierarchy Custom Settings, so we need to match the correct level.
                            They can be Org, Profile, or User level, so we query for all three, and then have to match them overriding higher level settings with lower level settings.
                            */
                            if(isCustomSetting)
                            {
                                Map<SObjectType,sobject> settings = new Map<SObjectType,sobject>();
                                for(sObject record: mapSObjects.values())
                                {
                                    Id setupOwnerId = String.valueOf( record.get('setupownerid') );
                                    settings.put(setupownerid.getsobjecttype(), record);
                                }
                                sObject matchingCustomSetting;
                                if(settings.containskey(organization.sobjecttype))
                                {
                                    matchingCustomSetting = settings.get(organization.sobjecttype);
                                    
                                }
                                if(settings.containskey(profile.sobjecttype))
                                {
                                    matchingCustomSetting = settings.get(profile.sobjecttype);
                                }
                                if(settings.containskey(user.sobjecttype))
                                {
                                    matchingCustomSetting = settings.get(user.sobjecttype);
                                }

                                if(matchingCustomSetting != null)
                                {
                                    mapSObjectRecords.put(objectType, new Map<Id, sObject> { matchingCustomSetting.Id => matchingCustomSetting } );
                                    System.debug('MESSAGINGCUSTOM TEMPLATE PROC -- Matching Hierarchy Custom Setting for "' + objectType + '" has been identified as: ' + matchingCustomSetting);
                                }                     
                            }
                            else
                            {
                                mapSObjectRecords.put(objectType, mapSObjects);
                            }

                            //Create a merge text to replacement value map
                            for(sObject record : mapSObjectRecords.get(objectType).values())
                            {
                                string key = record.Id;                                
                                if(objectType.equalsIgnoreCase('user') || objectType.equalsIgnoreCase('profile') || 
                                        objectType.equalsIgnoreCase('userrole') || objectType.equalsIgnoreCase('organization') || isCustomSetting)
                                {
                                    key = 'setup';
                                    if(isCustomSetting)
                                    {
                                        objectType = customSettingIdentifier+objectType;
                                    }
                                }

                                if(!mergeTextToValueMapPerRecord.containsKey(key))
                                    mergeTextToValueMapPerRecord.put(key, new Map<string,string>());

                                for(string mText : mapSObjectQueryFields.get(objectType).keySet())
                                {
                                    string temp = getFieldForRecord(record, mapSObjectQueryFields.get(objectType).get(mText));
                                    mergeTextToValueMapPerRecord.get(key).put(mText, (temp == null)?'':temp);
                                }
                            }

                            //Hardcode the other system variables
                            if(!mergeTextToValueMapPerRecord.containsKey('setup'))
                                    mergeTextToValueMapPerRecord.put('setup', new Map<string,string>());

                            mergeTextToValueMapPerRecord.get('setup').put('{!$Api.Session_ID}', UserInfo.getSessionId());
                            mergeTextToValueMapPerRecord.get('setup').put('{{$Api.Session_ID}}', UserInfo.getSessionId());
                            mergeTextToValueMapPerRecord.get('setup').put('{!$System.OriginDateTime}', DateTime.newInstance(0).format(DateTimeFormat));
                            mergeTextToValueMapPerRecord.get('setup').put('{{$System.OriginDateTime}}', DateTime.newInstance(0).format(DateTimeFormat));
                        }
                    }
                }
            }
        }
    }
    
    private void extractTemplateFields(String textToSearchForMergeFields, Map<string, Map<String, String>> mapSObjectQueryFields)
    {
        if(textToSearchForMergeFields==null) 
            return;

        Set<string> mergeTexts = new Set<String>();
        if(mapSObjectQueryFields==null)
        { 
            mapSObjectQueryFields = new Map<string, Map<String, String>>(); 
        }

        //We need to match 3 patterns:
        // {!test}  : Core
        // {#!test} : Raja's
        // {{test}} : Enhanced Email Action
        pattern myPattern = pattern.compile('(?m)\\{(\\{|#?!).+?(\\}|#)?\\}');
        matcher daMatcher = myPattern.matcher(textToSearchForMergeFields);
        while (daMatcher.find())
        { 
            string originalMatch = daMatcher.group();

            //remove the enclosing characters
            string match = originalMatch.replace('{{','').replace('}}','').replace('{!','').replace('{#!','').replace('}','').toLowerCase();
            //Custom settings start with $Setup, replace it with customSettingIdentifier
            if(match.startsWith('$setup'))
            {
                match = match.replace('$setup.','setup_');
            }
            else if(match.startsWith('$profile') || match.startsWith('$userrole') || match.startsWith('$organization') || match.startsWith('$user'))
            {
                match = match.replace('$','');
            }
            else if(match.startsWith('$'))
            {
                system.debug('MESSAGINGCUSTOM TEMPLATE PROC -- Found a system merge text that is not supported: '+ match);
                continue;
            }

            if(mergeIsNotField(match))
            {
                system.debug('MESSAGINGCUSTOM TEMPLATE PROC -- Found a system merge text that is not a field: '+ match);
                continue;
            }

            string objectName = match.substring(0,match.indexOf('.'));

            //Get the fields afther the object name. This could be: Field__c OR Field__r.Another__r.Name OR Special Formatting Fields like "Link"
            string objectFieldName = match.replace(objectName+'.','');             
            
            //Special merge fields formatting like Link, OwnerFullName, OwnerEmail, OwnerLastName, OwnerFirstName, RecordType
            //add additional fields here as needed and update methods FormatReferenceField, IsSObjectField, getFormattedMessage          
            if(objectFieldName.Contains('owner') || objectFieldName.Contains('recordtype'))
            {
                objectFieldName = formatReferenceField(objectFieldName);
                System.debug('MESSAGINGCUSTOM TEMPLATE PROC -- Formatted Reference Fields ' + objectFieldName );
            }
            //end special merge fields formatting
            
            if(objectName != null && objectFieldName != null)
            { 
                if(!mapSObjectQueryFields.containsKey(objectName))
                {
                    mapSObjectQueryFields.put(objectName, new Map<string,string>());
                }

                mapSObjectQueryFields.get(objectName).put(originalMatch, objectFieldName);
            }   
        }
    }

    private Boolean mergeIsNotField(string mergeText)
    {
        //This would only apply to VF templates
        //Thinking through all the possible VF Functions, they all require the use of parenthesis
        //However, when we are just referencing fields, we NEVER use a parenthesis.
        return mergeText.contains('(');
    }
    
    private string formatReferenceField(string aMergeFieldName)
    {
        
        if(aMergeFieldName.contains('recordtype') && !aMergeFieldName.contains('.'))
        {
            aMergeFieldName = aMergeFieldName.Replace('recordtype', 'RecordType.Name');
        } else if(aMergeFieldName.contains('ownerfullname'))
        {
            aMergeFieldName = aMergeFieldName.Replace('ownerfullname', 'Owner.Name');
        } else if(aMergeFieldName.contains('ownerfirstname'))
        {
            aMergeFieldName = aMergeFieldName.Replace('ownerfirstname','Owner.FirstName');
        } else if(aMergeFieldName.contains('ownerlastname'))
        {
            aMergeFieldName = aMergeFieldName.Replace('ownerlastname', 'Owner.LastName');
        } else if(aMergeFieldName.contains('owneremail'))
        {
            aMergeFieldName = aMergeFieldName.Replace('owneremail', 'Owner.Email');
        } else if(aMergeFieldName.contains('ownerphone'))
        {
            aMergeFieldName = aMergeFieldName.Replace('ownerphone','Owner.Phone');
        }
        
        return aMergeFieldName;
    }

    private void addIdToSObjectMap(ID anId)
    {
        string lObjectType = MessagingCustom.getObjectType(anId).toLowerCase();
        if(mapSObjectIds == null) 
            mapSObjectIds = new Map<string, Set<Id>>();

        if(!mapSObjectIds.containsKey(lObjectType))
        {
            mapSObjectIds.put(lObjectType,new Set<Id>());
        }
        mapSObjectIds.get(lObjectType).add(anId);
    }
    
    private string getFormattedMessage(string aMessage, string recordId)
    {
        if(aMessage == null || !mergeTextToValueMapPerRecord.containsKey(recordId))
            return aMessage;
        
        system.debug('MESSAGINGCUSTOM TEMPLATE PROC -- Getting formatted message for text: '+aMessage+' against record:' + recordId);
        Map<string,string> mergeTextToValueMap = mergeTextToValueMapPerRecord.get(recordId);
        for(string mergeText : mergeTextToValueMap.keyset())
        {
            string replaceValue = mergeTextToValueMap.get(mergeText);
            
            if(replaceValue != null)
            {
                aMessage = aMessage.replace(mergeText, replaceValue);
            } 
            else 
            {
                aMessage = aMessage.replace(mergeText, '');
            }
        }   
        return aMessage;
    }
    
    private string getFieldForRecord(sObject record, string field)
    {
        String returnValue = '';
        if(field.contains('.'))
        {
            string lRelatedObjectName = field.substring(0,field.indexOf('.'));
            string lRelatedFieldName = field.substring(field.indexOf('.')+1, field.length());
            system.debug('MESSAGINGCUSTOM TEMPLATE PROC -- Related Object Name = ' + lRelatedObjectName);    
            system.debug('MESSAGINGCUSTOM TEMPLATE PROC -- Related Field Name = ' + lRelatedFieldName);
            SObject relatedObject = record.getSObject(lRelatedObjectName);
            if(relatedObject == null)
            {
                return '';
            }
            returnValue = getFieldForRecord(relatedObject, lRelatedFieldName);
        }
        else if(field == 'link')
        {
            returnValue = URL.getSalesforceBaseUrl().toExternalForm() +  '/' + String.valueOf(record.Id);
        }
        else if(record.get(field) != null)
        {
            returnValue = String.ValueOf(record.get(field));
            string objName = record.getSobjectType().getDescribe().getName();

            Schema.DescribeFieldResult fieldDescribe = getObjectFieldDescribeResults(objName).get(field.toLowerCase().trim());

            if(fieldDescribe.getType() == Schema.DisplayType.DateTime)
            {
                DateTime tempDateTime = DateTime.valueOf(record.get(field));
                returnValue = tempDateTime.format(DateTimeFormat);
            }
            else if(fieldDescribe.getType() == Schema.DisplayType.Date)
            {
                Date tempDate = Date.valueOf(record.get(field));
                returnValue = tempDate.format();
            }
            else if(fieldDescribe.getType() == Schema.DisplayType.Boolean)
            {
                Boolean tempBool = Boolean.valueOf(record.get(field));
                returnValue = (tempBool)?'Yes':'No';
            }
        }

        system.debug('MESSAGINGCUSTOM TEMPLATE PROC -- Got value for ' + field + ', replaceValue = ' + returnValue);
        return returnValue;
    }       

    public static void getEmailTemplateAttachmentMap(Set<Id> templateIds)
    {
        Set<Id> newTemplateIdsToFetch = new Set<Id>();
        if(mapEmailTemplateAttachments == null)
        {
            mapEmailTemplateAttachments = new Map<Id,List<MessagingCustom.EmailFileAttachment>>();
            newTemplateIdsToFetch = templateIds;
        }
        else
        {
            for(Id templateId : templateIds)
            {
                if(!mapEmailTemplateAttachments.containsKey(templateId))
                    newTemplateIdsToFetch.add(templateId);
            }
        }

        for(Attachment att:[SELECT ContentType,Description,Id,Name,ParentId, Body FROM Attachment Where ParentId =:newTemplateIdsToFetch])
        {
            MessagingCustom.EmailFileAttachment emailAttachment = new MessagingCustom.EmailFileAttachment(att); 
            
            if(!mapEmailTemplateAttachments.containsKey(att.ParentId))
            {
                mapEmailTemplateAttachments.put(att.ParentId, new List<MessagingCustom.EmailFileAttachment>());
            }
            mapEmailTemplateAttachments.get(att.ParentId).add(emailAttachment);
            
         }
    }

    private static Map<string, Schema.DescribeFieldResult> getObjectFieldDescribeResults(string objectName)
    {
        if(cache_getObjectFieldDescribeResults == null)
            cache_getObjectFieldDescribeResults = new Map<string,Map<string, Schema.DescribeFieldResult>>();

        if(cache_getObjectFieldDescribeResults.containsKey(objectName))
        {
            return cache_getObjectFieldDescribeResults.get(objectName);
        }

        if(globalDescribe == null)
            globalDescribe = Schema.getGlobalDescribe();

        Schema.sObjectType objType = globalDescribe.get(objectName);//From the Object Api name retrieving the SObject
        // Describe the SObject using its object type.
        Schema.DescribeSObjectResult objDescribe = objType.getDescribe();       
        // Get a map of fields for the SObject
        Map<string, Schema.DescribeFieldResult> temp = new Map<string, Schema.DescribeFieldResult>();
        

        for(string field : objDescribe.fields.getMap().keySet())
        {
            Schema.DescribeFieldResult dr = objDescribe.fields.getMap().get(field).getDescribe();
            temp.put(field,dr);
        }

        cache_getObjectFieldDescribeResults.put(objectName, temp);
        return cache_getObjectFieldDescribeResults.get(objectName);
    }
}