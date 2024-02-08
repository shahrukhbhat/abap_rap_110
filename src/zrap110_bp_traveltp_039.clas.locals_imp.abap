**********************************************************************
**  Local Saver Class of Travel BO entity                           **
**********************************************************************
CLASS lsc_zrap110_r_traveltp_039 DEFINITION INHERITING FROM cl_abap_behavior_saver.

  PROTECTED SECTION.
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
              object            = 'ZRAP110039'  "Fallback: '/DMO/TRV_M'
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
  ENDMETHOD.
  METHOD get_instance_features.
  ENDMETHOD.

  METHOD acceptTravel.
  ENDMETHOD.

  METHOD createTravel.
  ENDMETHOD.

  METHOD recalcTotalPrice.
  ENDMETHOD.

  METHOD rejectTravel.
  ENDMETHOD.

  METHOD calculateTotalPrice.
  ENDMETHOD.

  METHOD setInitialTravelValues.
  ENDMETHOD.

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
