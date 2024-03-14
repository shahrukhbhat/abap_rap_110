**********************************************************************
**  Local Saver Class of Travel BO entity                           **
**********************************************************************
CLASS lsc_zrap110_r_traveltp_039 DEFINITION INHERITING FROM cl_abap_behavior_saver.

  PROTECTED SECTION.

    CONSTANTS:
      BEGIN OF travel_status,
        open     TYPE c LENGTH 1 VALUE 'O', "Open
        accepted TYPE c LENGTH 1 VALUE 'A', "Accepted
        rejected TYPE c LENGTH 1 VALUE 'X', "Rejected
      END OF travel_status.

    METHODS save_modified REDEFINITION.

    METHODS adjust_numbers REDEFINITION.

ENDCLASS.

CLASS lsc_zrap110_r_traveltp_039 IMPLEMENTATION.

  METHOD adjust_numbers.

    DATA: travel_id_max TYPE /dmo/travel_id.

    "Root BO entity: Travel
    IF mapped-travel IS NOT INITIAL.
      TRY.
          "get numbers
          cl_numberrange_runtime=>number_get(
            EXPORTING
              nr_range_nr       = '01'
              object            = '/DMO/TRV_M'   "'ZRAP110039'
              quantity          = CONV #( lines( mapped-travel ) )
            IMPORTING
              number            = DATA(number_range_key)
              returncode        = DATA(number_range_return_code)
              returned_quantity = DATA(number_range_returned_quantity)
          ).
        CATCH cx_number_ranges INTO DATA(lx_number_ranges).
          RAISE SHORTDUMP TYPE cx_number_ranges
            EXPORTING
              previous = lx_number_ranges.
      ENDTRY.

      ASSERT number_range_returned_quantity = lines( mapped-travel ).
      travel_id_max = number_range_key - number_range_returned_quantity.
      LOOP AT mapped-travel ASSIGNING FIELD-SYMBOL(<travel>).
        travel_id_max += 1.
        <travel>-TravelID = travel_id_max.
      ENDLOOP.
    ENDIF.
    "--------------insert the code for the booking entity below ---------

    "Child BO entity: Booking
    IF mapped-booking IS NOT INITIAL.
      READ ENTITIES OF ZRAP110_R_TravelTP_039 IN LOCAL MODE
        ENTITY Booking BY \_Travel
          FROM VALUE #( FOR booking IN mapped-booking WHERE ( %tmp-TravelID IS INITIAL )
                                                            ( %pid = booking-%pid
                                                              %key = booking-%tmp ) )
        LINK DATA(booking_to_travel_links).

      LOOP AT mapped-booking ASSIGNING FIELD-SYMBOL(<booking>).
        <booking>-TravelID =
          COND #( WHEN <booking>-%tmp-TravelID IS INITIAL
                  THEN mapped-travel[ %pid = booking_to_travel_links[ source-%pid = <booking>-%pid ]-target-%pid ]-TravelID
                  ELSE <booking>-%tmp-TravelID ).
      ENDLOOP.

      LOOP AT mapped-booking INTO DATA(mapped_booking) GROUP BY mapped_booking-TravelID.
        SELECT MAX( booking_id ) FROM zrap110_abook039 WHERE travel_id = @mapped_booking-TravelID INTO @DATA(max_booking_id) .
        LOOP AT GROUP mapped_booking ASSIGNING <booking>.
          max_booking_id += 10.
          <booking>-BookingID = max_booking_id.
        ENDLOOP.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD save_modified.
    "send notification for all accepted and rejected travel instances
    IF update IS NOT INITIAL.

      "raise event
      RAISE ENTITY EVENT ZRAP110_R_TravelTP_039~travel_accepted
       FROM VALUE #(
         FOR travel IN update-travel
         WHERE ( %control-OverallStatus EQ if_abap_behv=>mk-on AND
                 OverallStatus          EQ travel_status-accepted )
           "transferred information
           ( %key           = travel-%key
             travel_id      = travel-TravelID
             agency_id      = travel-AgencyID
             customer_id    = travel-CustomerID
             overall_status = travel-OverallStatus
             description    = travel-Description
             total_price    = travel-TotalPrice
             currency_code  = travel-CurrencyCode
             begin_date     = travel-BeginDate
             end_date       = travel-EndDate
           )
         ).

      "raise event
      RAISE ENTITY EVENT ZRAP110_R_TravelTP_039~travel_rejected
       FROM VALUE #(
         FOR travel IN update-travel
         WHERE ( %control-OverallStatus EQ if_abap_behv=>mk-on AND
                 OverallStatus          EQ travel_status-rejected )
           "transferred information
            ( %key = travel-%key )
         ).

    ENDIF.

  ENDMETHOD.

ENDCLASS.


**********************************************************************
**  Local Handler Class of Travel BO entity                         **
**********************************************************************
CLASS lhc_travel DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    CONSTANTS:
      "travel status
      BEGIN OF travel_status,
        open     TYPE c LENGTH 1 VALUE 'O', "Open
        accepted TYPE c LENGTH 1 VALUE 'A', "Accepted
        rejected TYPE c LENGTH 1 VALUE 'X', "Rejected
      END OF travel_status.

    METHODS:
      get_global_authorizations FOR GLOBAL AUTHORIZATION
        IMPORTING
        REQUEST requested_authorizations FOR Travel
        RESULT result,
      get_instance_features FOR INSTANCE FEATURES
        IMPORTING keys REQUEST requested_features FOR Travel RESULT result.

    METHODS acceptTravel FOR MODIFY
      IMPORTING keys FOR ACTION Travel~acceptTravel RESULT result.

    METHODS createTravel FOR MODIFY
      IMPORTING keys FOR ACTION Travel~createTravel.

    METHODS recalcTotalPrice FOR MODIFY
      IMPORTING keys FOR ACTION Travel~recalcTotalPrice.

    METHODS rejectTravel FOR MODIFY
      IMPORTING keys FOR ACTION Travel~rejectTravel RESULT result.

    METHODS calculateTotalPrice FOR DETERMINE ON MODIFY
      IMPORTING keys FOR Travel~calculateTotalPrice.

    METHODS setInitialTravelValues FOR DETERMINE ON MODIFY
      IMPORTING keys FOR Travel~setInitialTravelValues.

    METHODS validateAgency FOR VALIDATE ON SAVE
      IMPORTING keys FOR Travel~validateAgency.

    METHODS validateCustomer FOR VALIDATE ON SAVE
      IMPORTING keys FOR Travel~validateCustomer.

    METHODS validateDates FOR VALIDATE ON SAVE
      IMPORTING keys FOR Travel~validateDates.
ENDCLASS.

CLASS lhc_travel IMPLEMENTATION.
  METHOD get_global_authorizations.
    IF requested_authorizations-%create EQ if_abap_behv=>mk-on.
*     check create authorization
      AUTHORITY-CHECK OBJECT 'ZOSTAT039' ID 'ACTVT' FIELD '01'.
      result-%create = COND #( WHEN sy-subrc = 0 THEN
      if_abap_behv=>auth-allowed ELSE
      if_abap_behv=>auth-unauthorized ).
    ENDIF.

    IF requested_authorizations-%update EQ if_abap_behv=>mk-on.
*     check update authorization
      AUTHORITY-CHECK OBJECT 'ZOSTAT039' ID 'ACTVT' FIELD '02'.
      result-%update = COND #( WHEN sy-subrc = 0 THEN
      if_abap_behv=>auth-allowed ELSE
      if_abap_behv=>auth-unauthorized ).
    ENDIF.

    IF requested_authorizations-%delete EQ if_abap_behv=>mk-on.
*     check delete authorization
      AUTHORITY-CHECK OBJECT 'ZOSTAT039' ID 'ACTVT' FIELD '06'.
      result-%delete = COND #( WHEN sy-subrc = 0 THEN
      if_abap_behv=>auth-allowed ELSE
      if_abap_behv=>auth-unauthorized ).
    ENDIF.
  ENDMETHOD.
**************************************************************************
* Instance-bound dynamic feature control
**************************************************************************
  METHOD get_instance_features.
    " read relevant travel instance data
    READ ENTITIES OF ZRAP110_R_TravelTP_039 IN LOCAL MODE
      ENTITY travel
         FIELDS ( TravelID OverallStatus )
         WITH CORRESPONDING #( keys )
       RESULT DATA(travels)
       FAILED failed.

    " evaluate the conditions, set the operation state, and set result parameter
    result = VALUE #( FOR travel IN travels
                       ( %tky                   = travel-%tky

                         %features-%update      = COND #( WHEN travel-OverallStatus = travel_status-accepted
                                                          THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled   )

                         %features-%delete      = COND #( WHEN travel-OverallStatus = travel_status-open
                                                          THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled   )

                         %action-Edit           = COND #( WHEN travel-OverallStatus = travel_status-accepted
                                                            THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled   )

                         %action-acceptTravel   = COND #( WHEN travel-OverallStatus = travel_status-accepted
                                                              THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled   )

                         %action-rejectTravel   = COND #( WHEN travel-OverallStatus = travel_status-rejected
                                                            THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled   )
                      ) ).
  ENDMETHOD.

**************************************************************************
* Instance-bound action acceptTravel
**************************************************************************
  METHOD acceptTravel.
    MODIFY ENTITIES OF ZRAP110_R_TravelTP_039 IN LOCAL MODE
         ENTITY travel
            UPDATE FIELDS ( OverallStatus )
               WITH VALUE #( FOR key IN keys ( %tky         = key-%tky
                                               OverallStatus = travel_status-accepted ) ). " 'A' Accepted

    " read changed data for result
    READ ENTITIES OF ZRAP110_R_TravelTP_039 IN LOCAL MODE
      ENTITY travel
         ALL FIELDS WITH
         CORRESPONDING #( keys )
       RESULT DATA(travels).

    result = VALUE #( FOR travel IN travels ( %tky = travel-%tky  %param = travel ) ).
  ENDMETHOD.

**************************************************************************
* static default factory action createTravel
**************************************************************************
  METHOD createTravel.

    IF keys IS NOT INITIAL.
      SELECT * FROM /dmo/flight FOR ALL ENTRIES IN @keys WHERE carrier_id    = @keys-%param-carrier_id
                                                         AND   connection_id = @keys-%param-connection_id
                                                         AND   flight_date   = @keys-%param-flight_date
                                                         INTO TABLE @DATA(flights).

      "create travel instances with default bookings
      MODIFY ENTITIES OF zrap110_r_traveltp_039 IN LOCAL MODE
        ENTITY Travel
          CREATE
            FIELDS ( CustomerID Description )
              WITH VALUE #( FOR key IN keys ( %cid = key-%cid
                                              %is_draft = key-%param-%is_draft
                                              CustomerID = key-%param-customer_id
                                              Description = 'Own Create Implementation' ) )
          CREATE BY \_Booking
            FIELDS ( CustomerID CarrierID ConnectionID FlightDate FlightPrice CurrencyCode )
              WITH VALUE #( FOR key IN keys INDEX INTO i
                          ( %cid_ref  = key-%cid
                            %is_draft = key-%param-%is_draft
                            %target   = VALUE #( ( %cid         = i
                                                   %is_draft    = key-%param-%is_draft
                                                   CustomerID   = key-%param-customer_id
                                                   CarrierID    = key-%param-carrier_id
                                                   ConnectionID = key-%param-connection_id
                                                   FlightDate   = key-%param-flight_date
                                                   FlightPrice  = VALUE #( flights[ carrier_id    = key-%param-carrier_id
                                                                                    connection_id = key-%param-connection_id
                                                                                    flight_date   = key-%param-flight_date ]-price OPTIONAL )
                                                   CurrencyCode = VALUE #( flights[ carrier_id    = key-%param-carrier_id
                                                                                    connection_id = key-%param-connection_id
                                                                                    flight_date   = key-%param-flight_date ]-currency_code OPTIONAL )
                          ) ) ) )
      MAPPED mapped.
    ENDIF.

  ENDMETHOD.

**************************************************************************
* Internal instance-bound action calculateTotalPrice
**************************************************************************
  METHOD reCalctotalprice.
    TYPES: BEGIN OF ty_amount_per_currencycode,
             amount        TYPE /dmo/total_price,
             currency_code TYPE /dmo/currency_code,
           END OF ty_amount_per_currencycode.

    DATA: amounts_per_currencycode TYPE STANDARD TABLE OF ty_amount_per_currencycode.

    " Read all relevant travel instances.
    READ ENTITIES OF ZRAP110_R_TravelTP_039 IN LOCAL MODE
         ENTITY Travel
            FIELDS ( BookingFee CurrencyCode )
            WITH CORRESPONDING #( keys )
         RESULT DATA(travels).

    DELETE travels WHERE CurrencyCode IS INITIAL.

    " Read all associated bookings and add them to the total price.
    READ ENTITIES OF ZRAP110_R_TravelTP_039 IN LOCAL MODE
      ENTITY Travel BY \_Booking
        FIELDS ( FlightPrice CurrencyCode )
      WITH CORRESPONDING #( travels )
      LINK DATA(booking_links)
      RESULT DATA(bookings).

    LOOP AT travels ASSIGNING FIELD-SYMBOL(<travel>).
      " Set the start for the calculation by adding the booking fee.
      amounts_per_currencycode = VALUE #( ( amount        = <travel>-bookingfee
                                            currency_code = <travel>-currencycode ) ).

      LOOP AT booking_links INTO DATA(booking_link) USING KEY id WHERE source-%tky = <travel>-%tky.
        " Short dump occurs if link table does not match read table, which must never happen
        DATA(booking) = bookings[ KEY id  %tky = booking_link-target-%tky ].
        COLLECT VALUE ty_amount_per_currencycode( amount        = booking-flightprice
                                                  currency_code = booking-currencycode ) INTO amounts_per_currencycode.
      ENDLOOP.

      DELETE amounts_per_currencycode WHERE currency_code IS INITIAL.

      CLEAR <travel>-TotalPrice.
      LOOP AT amounts_per_currencycode INTO DATA(amount_per_currencycode).
        " If needed do a Currency Conversion
        IF amount_per_currencycode-currency_code = <travel>-CurrencyCode.
          <travel>-TotalPrice += amount_per_currencycode-amount.
        ELSE.
          /dmo/cl_flight_amdp=>convert_currency(
             EXPORTING
               iv_amount                   =  amount_per_currencycode-amount
               iv_currency_code_source     =  amount_per_currencycode-currency_code
               iv_currency_code_target     =  <travel>-CurrencyCode
               iv_exchange_rate_date       =  cl_abap_context_info=>get_system_date( )
             IMPORTING
               ev_amount                   = DATA(total_booking_price_per_curr)
            ).
          <travel>-TotalPrice += total_booking_price_per_curr.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    " write back the modified total_price of travels
    MODIFY ENTITIES OF ZRAP110_R_TravelTP_039 IN LOCAL MODE
      ENTITY travel
        UPDATE FIELDS ( TotalPrice )
        WITH CORRESPONDING #( travels ).

  ENDMETHOD.

**************************************************************************
* Instance-bound action rejectTravel
**************************************************************************
  METHOD rejectTravel.
    MODIFY ENTITIES OF ZRAP110_R_TravelTP_039 IN LOCAL MODE
         ENTITY travel
            UPDATE FIELDS ( OverallStatus )
               WITH VALUE #( FOR key IN keys ( %tky         = key-%tky
                                               OverallStatus = travel_status-rejected ) ). " 'X' Rejected

    " read changed data for result
    READ ENTITIES OF ZRAP110_R_TravelTP_039 IN LOCAL MODE
      ENTITY travel
         ALL FIELDS WITH
         CORRESPONDING #( keys )
       RESULT DATA(travels).

    result = VALUE #( FOR travel IN travels ( %tky = travel-%tky  %param = travel ) ).
  ENDMETHOD.

**************************************************************************
* determination calculateTotalPrice
**************************************************************************
  METHOD calculateTotalPrice.
    MODIFY ENTITIES OF ZRAP110_R_TravelTP_039 IN LOCAL MODE
      ENTITY Travel
        EXECUTE reCalcTotalPrice
        FROM CORRESPONDING #( keys ).

  ENDMETHOD.
**************************************************************************
* determination setInitialTravelValues: BeginDate, EndDate
**************************************************************************
  METHOD setInitialTravelValues.
    READ ENTITIES OF ZRAP110_R_TravelTP_039 IN LOCAL MODE
      ENTITY Travel
        FIELDS ( BeginDate EndDate CurrencyCode OverallStatus )
        WITH CORRESPONDING #( keys )
      RESULT DATA(travels).

    DATA: update TYPE TABLE FOR UPDATE zrap110_r_traveltp_039\\Travel.
    update = CORRESPONDING #( travels ).
    DELETE update WHERE BeginDate IS NOT INITIAL AND EndDate IS NOT INITIAL
                    AND CurrencyCode IS NOT INITIAL AND OverallStatus IS NOT INITIAL.

    LOOP AT update ASSIGNING FIELD-SYMBOL(<update>).
      IF <update>-BeginDate IS INITIAL.
        <update>-BeginDate     = cl_abap_context_info=>get_system_date( ) + 1.
        <update>-%control-BeginDate = if_abap_behv=>mk-on.
      ENDIF.
      IF <update>-EndDate  IS INITIAL.
        <update>-EndDate       = cl_abap_context_info=>get_system_date( ) + 15.
        <update>-%control-EndDate = if_abap_behv=>mk-on.
      ENDIF.
      IF <update>-CurrencyCode IS INITIAL.
        <update>-CurrencyCode  = 'EUR'.
        <update>-%control-CurrencyCode = if_abap_behv=>mk-on.
      ENDIF.
      IF <update>-OverallStatus IS INITIAL.
        <update>-OverallStatus = travel_status-open.
        <update>-%control-OverallStatus = if_abap_behv=>mk-on.
      ENDIF.
    ENDLOOP.

    IF update IS NOT INITIAL.
      MODIFY ENTITIES OF ZRAP110_R_TravelTP_039 IN LOCAL MODE
      ENTITY Travel
        UPDATE FROM update.
    ENDIF.
  ENDMETHOD.

**************************************************************************
* Validation for AgencyID
**************************************************************************
  METHOD validateAgency.
    " Read relevant travel instance data
    READ ENTITIES OF ZRAP110_R_TravelTP_039 IN LOCAL MODE
    ENTITY travel
     FIELDS ( AgencyID )
     WITH CORRESPONDING #(  keys )
    RESULT DATA(travels).

    DATA agencies TYPE SORTED TABLE OF /dmo/agency WITH UNIQUE KEY agency_id.

    " Optimization of DB select: extract distinct non-initial agency IDs
    agencies = CORRESPONDING #( travels DISCARDING DUPLICATES MAPPING agency_id = AgencyID EXCEPT * ).
    DELETE agencies WHERE agency_id IS INITIAL.

    IF  agencies IS NOT INITIAL.
      " check if agency ID exist
      SELECT FROM /dmo/agency FIELDS agency_id
        FOR ALL ENTRIES IN @agencies
        WHERE agency_id = @agencies-agency_id
        INTO TABLE @DATA(agencies_db).
    ENDIF.

    " Raise msg for non existing and initial agency id
    LOOP AT travels INTO DATA(travel).
      APPEND VALUE #(  %tky        = travel-%tky
                       %state_area = 'VALIDATE_AGENCY'
                     ) TO reported-travel.

      IF travel-AgencyID IS INITIAL OR NOT line_exists( agencies_db[ agency_id = travel-AgencyID ] ).
        APPEND VALUE #(  %tky = travel-%tky ) TO failed-travel.
        APPEND VALUE #(  %tky = travel-%tky
                         %state_area = 'VALIDATE_AGENCY'
                         %msg = NEW /dmo/cm_flight_messages(
                                          textid    = /dmo/cm_flight_messages=>agency_unkown
                                          agency_id = travel-AgencyID
                                          severity  = if_abap_behv_message=>severity-error )
                         %element-AgencyID = if_abap_behv=>mk-on
                      ) TO reported-travel.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

**************************************************************************
* Validation for CustomerID
**************************************************************************
  METHOD validateCustomer.
    "read relevant travel instance data
    READ ENTITIES OF ZRAP110_R_TravelTP_039 IN LOCAL MODE
    ENTITY Travel
     FIELDS ( CustomerID )
     WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

    DATA customers TYPE SORTED TABLE OF /dmo/customer WITH UNIQUE KEY customer_id.

    "optimization of DB select: extract distinct non-initial customer IDs
    customers = CORRESPONDING #( travels DISCARDING DUPLICATES MAPPING customer_id = customerID EXCEPT * ).
    DELETE customers WHERE customer_id IS INITIAL.

    IF customers IS NOT INITIAL.
      "check if customer ID exists
      SELECT FROM /dmo/customer FIELDS customer_id
                                FOR ALL ENTRIES IN @customers
                                WHERE customer_id = @customers-customer_id
        INTO TABLE @DATA(valid_customers).
    ENDIF.

    "raise msg for non existing and initial customer id
    LOOP AT travels INTO DATA(travel).
      APPEND VALUE #(  %tky        = travel-%tky
                       %state_area = 'VALIDATE_CUSTOMER'
                     ) TO reported-travel.

      IF travel-CustomerID IS  INITIAL.
        APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.

        APPEND VALUE #( %tky        = travel-%tky
                        %state_area = 'VALIDATE_CUSTOMER'
                        %msg        = NEW /dmo/cm_flight_messages(
                                        textid   = /dmo/cm_flight_messages=>enter_customer_id
                                        severity = if_abap_behv_message=>severity-error )
                        %element-CustomerID = if_abap_behv=>mk-on
                      ) TO reported-travel.

      ELSEIF travel-CustomerID IS NOT INITIAL AND NOT line_exists( valid_customers[ customer_id = travel-CustomerID ] ).
        APPEND VALUE #(  %tky = travel-%tky ) TO failed-travel.

        APPEND VALUE #(  %tky        = travel-%tky
                         %state_area = 'VALIDATE_CUSTOMER'
                         %msg        = NEW /dmo/cm_flight_messages(
                                         customer_id = travel-customerid
                                         textid      = /dmo/cm_flight_messages=>customer_unkown
                                         severity    = if_abap_behv_message=>severity-error )
                         %element-CustomerID = if_abap_behv=>mk-on
                      ) TO reported-travel.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

**************************************************************************
* Validation for BeginDate and EndDate
**************************************************************************
  METHOD validateDates.
    READ ENTITIES OF ZRAP110_R_TravelTP_039 IN LOCAL MODE
       ENTITY travel
         FIELDS ( BeginDate EndDate )
         WITH CORRESPONDING #( keys )
       RESULT DATA(travels).

    LOOP AT travels INTO DATA(travel).
      APPEND VALUE #(  %tky        = travel-%tky
                       %state_area = 'VALIDATE_DATES' ) TO reported-travel.

      IF travel-EndDate < travel-BeginDate.                                 "end_date before begin_date
        APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.
        APPEND VALUE #( %tky = travel-%tky
                        %state_area = 'VALIDATE_DATES'
                        %msg = NEW /dmo/cm_flight_messages(
                                   textid     = /dmo/cm_flight_messages=>begin_date_bef_end_date
                                   severity   = if_abap_behv_message=>severity-error
                                   begin_date = travel-BeginDate
                                   end_date   = travel-EndDate
                                   travel_id  = travel-TravelID )
                        %element-BeginDate    = if_abap_behv=>mk-on
                        %element-EndDate      = if_abap_behv=>mk-on
                     ) TO reported-travel.

      ELSEIF travel-BeginDate < cl_abap_context_info=>get_system_date( ).  "begin_date must be in the future
        APPEND VALUE #( %tky        = travel-%tky ) TO failed-travel.
        APPEND VALUE #( %tky = travel-%tky
                        %state_area = 'VALIDATE_DATES'
                        %msg = NEW /dmo/cm_flight_messages(
                                    textid   = /dmo/cm_flight_messages=>begin_date_on_or_bef_sysdate
                                    severity = if_abap_behv_message=>severity-error )
                        %element-BeginDate  = if_abap_behv=>mk-on
                        %element-EndDate    = if_abap_behv=>mk-on
                      ) TO reported-travel.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
