/*
    Copyright (c) 2017, Salesforce.org
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Salesforce.org nor the names of
      its contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
    COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
*/
/**
* @author Salesforce.org
* @date 2017
* @group Rollups
* @group-content ../../ApexDocContent/Rollups2.htm
* @description Wrapper class of properties to be tracked for each rollup across all of the Detail records.
* This class is used to hold all rollup data across a rollup operation; including operations that are stateful
* in a batch process.
*
*/
public class CRLP_Rollup {

    private static CRLP_FiscalYears fiscalYrs;

    public List<Rollup__mdt> rollupsMdt;
    public String resultFieldName;
    public SoapType resultFieldType;
    public Boolean useFiscalYear;
    public String detailObject;
    public String amountObject;
    public String dateObject;
    public String currCode;     // The currency code of the target (summary) object
    public String yearlyOperation;
    public Integer daysBack;

    // Basic counter vars
    public Integer theCount;        // count, average
    public Decimal theSum;          // sum, average
    public Decimal maxValue;        // smallest/largest
    public Decimal minValue;        // smallest/largest
    public Date maxDate;            // first/last
    public Date minDate;            // first/last
    public DateTime maxDateTime;    // first/last
    public DateTime minDateTime;    // first/last

    // Vars to handle using a different field for the summary. For example, might have Largest as the Operation
    // against the Opportunity.Amount, but the ResultField might pull in Opportunity.Id or any field from the
    // Opportunity object.
    // Using Two-dimensional array to store first/last values for all the various data types. For example,
    // might have a rollup of "Id of the first donation", "Amount of the last donation",
    // or "{some text field} from first donation"
    public String[] textValue;
    public Decimal[] numValue;
    public Id[] idValue;
    public Date dateValue;
    public DateTime dateTimeValue;

    // Maps of rolled up stats by year; where the map key is the year (fiscal or calendar) from the specified date field
    public Map<String, Double> sumByYear;
    public Map<String, Double> minByYear;
    public Map<String, Double> maxByYear;
    public Map<String, Integer> countByYear;

    /** @description Constructor */
    public CRLP_Rollup(Rollup__mdt rollupMdt) {
        if (this.rollupsMdt == null) {
            this.rollupsMdt = new List<Rollup__mdt>();

            // Field and Object details
            this.amountObject = rollupMdt.Amount_Object__r.QualifiedApiName;
            this.dateObject = rollupMdt.Date_Object__r.QualifiedApiName;
            this.detailObject = rollupMdt.Detail_Object__r.QualifiedApiName;
            if (rollupMdt.Detail_Field__c !=  null) {
                DescribeFieldResult resultField = CRLP_Rollup_SVC.getSObjectFieldDescribe(detailObject, rollupMdt.Detail_Field__r.QualifiedApiName);
                this.resultFieldType = resultField.getSoapType();
                this.resultFieldName = resultField.getName();
            }

            // Year and Date/Day related details
            this.useFiscalYear = rollupMdt.Use_Fiscal_Year__c;
            this.yearlyOperation = rollupMdt.Yearly_Operation_Type__c;
            if (this.yearlyOperation == CRLP_Operation.YearlyOperationType.DAYS_BACK.name()) {
                this.daysBack = Integer.valueOf(rollupMdt.Integer__c);
            }

            // Clear all the counter values
            resetValues();
        }
        this.rollupsMdt.add(rollupMdt);
    }

    /** @description Reset all counter vars to 0/null */
    public void resetValues() {
        this.theCount = 0;
        this.theSum = this.minValue = this.maxValue = 0;
        this.dateValue = this.minDate = this.maxDate = null;
        this.dateTimeValue = this.minDateTime = this.maxDateTime = null;

        this.minByYear = new Map<String, Double>();
        this.maxByYear = new Map<String, Double>();
        this.sumByYear = new Map<String, Double>();
        this.countByYear = new Map<String, Integer>();

        this.textValue = new List<String>{ null, null };
        this.numValue = new List<Decimal>{ 0, 0 };
        this.idValue = new List<Id>{ null, null };
    }

    /**
     * @description Set the currency code of the target (Summary) record. This will be used for converting the
     * detail record amount values to the currency of the target record.
     * @param currencyIsoCode
     */
    public void setCurrencyCode(String currCode) {
        this.currCode = currCode;
    }

    /**
     * @description Determine if the passed Rollup__mdt record has the identical key properties to this
     * Rollup instance: FilterGroup, UseFiscalYear, Detail Field, Use_OCR_for_Attribution_Object__c Field,
     * Amount Field and Date Field.
     * @param Rollup__mdt
     * @return True or False
     */
    public Boolean isRollupInSameGroup(Rollup__mdt otherMdtRollup) {
        Set<String> matchingFields = new Set<String>{
                'Filter_Group__c','Detail_Field__c', 'Use_OCR_for_Attribution_Object__c',
                'Date_Field__c', 'Amount_Field__c', 'Use_Fiscal_Year__c', 'Yearly_Operation_Type__c'
        };
        if (this.rollupsMdt == null) {
            return true;
        }

        // Due to the large variation of possible combinations, Rollups for DAYS_BACK YearlyOperation
        // types cannot be combined with other rollups of different types/days.
        if (this.yearlyOperation == CRLP_Operation.YearlyOperationType.DAYS_BACK.name()
                && this.daysBack != otherMdtRollup.Integer__c) {
            return false;
        }

        Rollup__mdt rollupItem = this.rollupsMdt[0];
        for (String fld : matchingFields) {
            if (rollupItem.get(fld) != otherMdtRollup.get(fld)) {
                return false;
            }
        }
        return true;
    }

    /**
     * @description Returns the appropriate return for this rollup based on the rollup operation type
     * and the target field data type
     */
    public Map<String, Object> getFinalValues() {
        Map<String, Object> rtnValues = new Map<String, Object>();

        // Instantiate this with the first Rollup__mdt record. All records have the same
        // value in the Use_Fiscal_Year__c field.
        fiscalYrs = new CRLP_FiscalYears(this.useFiscalYear);
        UTIL_Debug.debug('> Rollup=' + this);

        // Get the rolled up value for each Rollup__mdt record
        for (Rollup__mdt r : this.rollupsMdt) {
            Schema.DescribeFieldResult targetField = CRLP_Rollup_SVC.getSObjectFieldDescribe(r.Summary_Object__r.QualifiedApiName, r.Summary_Field__r.QualifiedApiName);
            rtnValues.put(targetField.getName(), determineRollupValue(r, targetField));
        }

        return rtnValues;
    }

    /**
     * @description For a given Rollup__mdt, retrieve the correct rolled-up value using the class instance vars
     * @param Rollup__mdt
     * @param targetField DescribeFieldResult for the target (Summary) field
     * @return Object with the return value to be stored in the target field
     */
    private Object determineRollupValue(Rollup__mdt r, DescribeFieldResult targetField) {
        SoapType fldType = targetField.getSoapType();
        Object resultValue;

        CRLP_Operation.RollupType operation = CRLP_Operation.getRollupTypeFromString(r.Operation__c.replaceAll(' ', '_'));

        // ================================================================
        // Yearly Operation Type - Get the Sum/Min/Max for the specified number of years back to use
        // in the later logic to determine the values to return for this rollup.
        // ================================================================
        Decimal sumForSpecifiedYear = 0, maxForSpecifiedYear = 0, minForSpecifiedYear = 0, countForSpecifiedYear = 0;
        Boolean useYearsAgoValue = ( this.yearlyOperation == CRLP_Operation.YearlyOperationType.YEARS_AGO.name());
        if (useYearsAgoValue == true) {
            // Find the data for the specified number of years back.
            Integer getThisYear = (this.useFiscalYear ? fiscalYrs.getYear(Date.Today()) : Date.Today().Year()) - r.Integer__c.intValue();
            String yrString = getThisYear.format().replace(',','');
            // If the map of sums by year include the specified year, then get the Sum/Min/Max
            if (sumByYear.containsKey(yrString)) {
                sumForSpecifiedYear += sumByYear.get(yrString);
                minForSpecifiedYear += maxByYear.get(yrString);
                maxForSpecifiedYear += minByYear.get(yrString);
                countForSpecifiedYear += countByYear.get(yrString);
            }
        }

        // ================================================================
        // Simple ResultField types
        // ================================================================
        /*if (this.resultFieldType != null) {
            if (this.resultFieldType == SoapType.DATE) {
                resultValue = this.dateValue;
            } else if (this.resultFieldType == SoapType.DATETIME) {
                resultValue = this.dateTimeValue;
            } else if (this.resultFieldType == SoapType.ID) {
                resultValue = this.idValue;
            } else {
                resultValue = this.textValue;
            }
        }*/

        // ================================================================
        // First/Last Donation Date or DateTime
        // ================================================================
        if (fldType == SoapType.DATE && operation == CRLP_Operation.RollupType.FIRST) {
            resultValue = minDate;
        } else if (fldType == SoapType.DATE && operation == CRLP_Operation.RollupType.LAST) {
            resultValue = maxDate;
        } else if (fldType == SoapType.DATETIME && operation == CRLP_Operation.RollupType.FIRST) {
            resultValue = minDateTime;
        } else if (fldType == SoapType.DATETIME && operation == CRLP_Operation.RollupType.LAST) {
            resultValue = maxDateTime;
        }

        // ================================================================
        // First/Last of some value not of a Date or DateTime type,such as "Last Gift Amount"
        // This could be an Id or pretty much any other field that can be stored as 'text'
        // ================================================================
        else if (operation == CRLP_Operation.RollupType.FIRST || operation == CRLP_Operation.RollupType.LAST) {
            if (fldType == SoapType.DOUBLE) {
                resultValue = numValue[(operation == CRLP_Operation.RollupType.FIRST ? 0 : 1)];
            } else if (fldType == SoapType.ID) {
                resultValue = idValue[(operation == CRLP_Operation.RollupType.FIRST ? 0 : 1)];
            } else {
                resultValue = textValue[(operation == CRLP_Operation.RollupType.FIRST ? 0 : 1)];
            }
        }

        // ================================================================
        // Sum, Average, Largest, Smallest, Count
        // ================================================================
        else if (fldType == SoapType.DOUBLE && operation == CRLP_Operation.RollupType.SUM) {
            if (useYearsAgoValue == false) {
                resultValue = theSum;
            } else {
                resultValue = sumForSpecifiedYear;
            }
        } else if (fldType == SoapType.DOUBLE && operation == CRLP_Operation.RollupType.AVERAGE) {
            if (useYearsAgoValue == false && theCount != 0) {
                resultValue = theSum.divide(theCount, 2, RoundingMode.HALF_UP);
            } else if (countForSpecifiedYear != 0) {
                resultValue = sumForSpecifiedYear.divide(countForSpecifiedYear, 2, RoundingMode.HALF_UP);
            } else {
                resultValue = 0;
            }
        } else if (fldType == SoapType.DOUBLE && operation == CRLP_Operation.RollupType.SMALLEST) {
            if (useYearsAgoValue == false) {
                resultValue = minValue;
            } else {
                resultValue = minForSpecifiedYear;
            }
        } else if (fldType == SoapType.DOUBLE && operation == CRLP_Operation.RollupType.LARGEST) {
            if (useYearsAgoValue == false) {
                resultValue = maxValue;
            } else {
                resultValue = maxForSpecifiedYear;
            }
        } else if (fldType == SoapType.DOUBLE && operation == CRLP_Operation.RollupType.COUNT) {
            if (useYearsAgoValue == false) {
                resultValue = theCount;
            } else {
                resultValue = countForSpecifiedYear;
            }
        }

        // ================================================================
        // Best Year or Best Year Total
        // ================================================================
        else if (operation == CRLP_Operation.RollupType.BEST_YEAR || operation == CRLP_Operation.RollupType.BEST_YEAR_TOTAL) {
            Double maxVal = 0;
            String bestYr = null;
            for (String yr : this.sumByYear.keySet()) {
                if (this.sumByYear.get(yr) > maxVal) {
                    bestYr = yr;
                    maxVal = this.sumByYear.get(yr);
                }
            }
            if (operation == CRLP_Operation.RollupType.BEST_YEAR_TOTAL) {
                resultValue = maxVal;
            } else {
                if (bestYr == null || fldType == SoapType.STRING) {
                    resultValue = bestYr;
                } else if (fldType == SoapType.DOUBLE) {
                    resultValue = Integer.valueOf(bestYr);
                }
            }
        }

        // ================================================================
        // Years Donated (semi-colon separated list)
        // ================================================================
        else if (operation == CRLP_Operation.RollupType.YEARS_DONATED) {
            List<String> years = new List<String>( this.sumByYear.keySet() );
            years.sort();
            resultValue = (!years.isEmpty() ? String.join(years,';') : null);
        }

        // ================================================================
        // Current Streak (returns the number of years going back from this yer that a donation has been made)
        // ================================================================
        else if (operation == CRLP_Operation.RollupType.CURRENT_STREAK) {
            List<String> yearlySorted = new List<String>( this.sumByYear.keySet() );
            yearlySorted.sort();
            Integer streakLength = 0;

            Integer currentYear = fiscalYrs.getYear(System.today());
            if (currentYear != Integer.valueOf(yearlySorted[yearlySorted.size()-1])) {
                // if they haven't donated this year, start counting last year
                currentYear--;
            }

            // Loop through all the years with donations in reverse to find the current streak
            for (Integer n=yearlySorted.size()-1; n >= 0 ; n--) {
                if (Integer.valueOf(yearlySorted[n]) == currentYear) {
                    streakLength++;
                    currentYear--;
                } else {
                    break;
                }
            }
            resultValue = streakLength;
        }

        return resultValue;
    }
}