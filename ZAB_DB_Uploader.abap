*&---------------------------------------------------------------------*
*&Program Name  :   ZAB_DB_UPLOADER                                    *
*&Title         :   DB Uploader Program                                *
*&Developer     :   Sai Bharadwaj Apparaju                             *                                      *
*&Description   :   This Report will upload data into database tables  *
*&                  (Custom Tables / Z* / Y* tables ) from a .xlsx file*
*&                  After Successful Execution of the program an ALV   *
*&                  will be displayed showing the number of Successful *
*&                  and failed entries                                 *
*&---------------------------------------------------------------------*
REPORT zab_demo012.

*--Selection Screen

SELECTION-SCREEN BEGIN OF BLOCK b1.
  PARAMETERS: p_table TYPE dd02l-tabname AS LISTBOX DEFAULT '*ZTABLE*' OBLIGATORY VISIBLE LENGTH 20 USER-COMMAND dd,
              p_file  LIKE rlgrap-filename.
SELECTION-SCREEN END OF BLOCK b1.

*--Declarations

DATA: gt_dyn_data   TYPE REF TO data,
      gs_dyn_data   TYPE REF TO data,
      gv_success    TYPE i,
      gv_error      TYPE i,
      gr_table      TYPE REF TO cl_salv_table,
      go_header     TYPE REF TO cl_salv_form_layout_grid,
      go_cols       TYPE REF TO cl_salv_columns_table,
      gr_functions  TYPE REF TO cl_salv_functions,
      gt_vrm_values TYPE vrm_values,
      gt_fcat       TYPE lvc_t_fcat,
      go_strucdescr TYPE REF TO cl_abap_structdescr,
      gt_tab_fields TYPE ddfields,
      gt_excel_raw  TYPE STANDARD TABLE OF alsmex_tabline WITH NON-UNIQUE DEFAULT KEY.

CONSTANTS gc_vrm_id TYPE vrm_id VALUE 'P_TABLE'.

FIELD-SYMBOLS: <gft_data> TYPE STANDARD TABLE,
               <gfs_data> TYPE any.

*--File Open Dialog

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.
  PERFORM f4_help.

*--Drop-down

AT SELECTION-SCREEN OUTPUT.
  PERFORM  get_dropdown_list.

START-OF-SELECTION.
*--Mandatory Check

  PERFORM mandt_check.

*--Get the contents of the Excel file into an itab.

  PERFORM get_data USING    p_file
  CHANGING gt_excel_raw.

*--Create dynamic internal table

  PERFORM create_dyn_table.

*--Reorganize excel data

  PERFORM reorganize_excel_data.

*--Remove Duplicates

  PERFORM remove_duplicates.

*--Load Data to DB

  PERFORM load_to_db.

*--Display result.

  PERFORM display_result.

*&---------------------------------------------------------------------*
*& Form f4_help
*&---------------------------------------------------------------------*
FORM f4_help.
  DATA: lt_file_table TYPE filetable,
        lv_rc         TYPE i.
  CLEAR: lt_file_table[],lv_rc.
  CALL METHOD cl_gui_frontend_services=>file_open_dialog
    CHANGING
      file_table = lt_file_table
      rc         = lv_rc.
  IF lt_file_table IS NOT INITIAL.
    p_file  =  VALUE #( lt_file_table[ 1 ]-filename OPTIONAL ).
  ELSE.
    LEAVE LIST-PROCESSING.
  ENDIF.
ENDFORM.
*&---------------------------------------------------------------------*
*& Form get_dropdown_list
*&---------------------------------------------------------------------*
FORM get_dropdown_list .
  CLEAR: gt_vrm_values[].
  gt_vrm_values = VALUE #( BASE gt_vrm_values ( key = '*ZTABLE1*'     text = '*ZTABLE1*'     )
                                              ( key = '*ZTABLE2*'     text = '*ZTABLE2*'     )
                                              ( key = '*ZTABLE3*'     text = '*ZTABLE3*'     )
                                              ( key = '*ZTABLE4*'     text = '*ZTABLE4*'     )
                                              ( key = '*ZTABLE5*'     text = '*ZTABLE5*'     ) ).
  CALL FUNCTION 'VRM_SET_VALUES'
    EXPORTING
      id     = gc_vrm_id
      values = gt_vrm_values.
ENDFORM.
*&---------------------------------------------------------------------*
*& Form mandt_check
*&---------------------------------------------------------------------*
FORM mandt_check .
  IF p_file IS INITIAL.
    MESSAGE 'File should be Mandatory' TYPE 'I' DISPLAY LIKE 'E'.
    LEAVE LIST-PROCESSING.
  ENDIF.
ENDFORM.
*&---------------------------------------------------------------------*
*& Form get_data
*&---------------------------------------------------------------------*
FORM get_data  USING    p_file
CHANGING pt_excel LIKE gt_excel_raw.
  CALL FUNCTION 'ALSM_EXCEL_TO_INTERNAL_TABLE'
    EXPORTING
      filename                = p_file
      i_begin_col             = 1
      i_begin_row             = 2     "It is assumed that first row in the excel is the header
      i_end_col               = 200
      i_end_row               = 50000 "It is assumed that the excel sheet would not have more than this number of rows.
    TABLES
      intern                  = pt_excel
    EXCEPTIONS
      inconsistent_parameters = 1
      upload_ole              = 2
      OTHERS                  = 3.
  IF sy-subrc NE 0.
    MESSAGE ID sy-msgid TYPE 'I' NUMBER sy-msgno
    WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4
    DISPLAY LIKE 'E'.
    LEAVE LIST-PROCESSING.
  ENDIF.
ENDFORM.
*&---------------------------------------------------------------------*
*& Form reorganize_excel_data
*&---------------------------------------------------------------------*
FORM reorganize_excel_data.
  DATA lv_i TYPE i.
  LOOP AT gt_excel_raw ASSIGNING FIELD-SYMBOL(<lfs_raw>).
    lv_i = <lfs_raw>-col.
    lv_i = lv_i + 1.
    ASSIGN COMPONENT lv_i OF STRUCTURE <gfs_data> TO FIELD-SYMBOL(<lfs_field>).
    IF sy-subrc EQ 0.
      CONDENSE <lfs_raw>-value.
      <lfs_field> = <lfs_raw>-value.
    ENDIF.
    AT END OF row.
      ASSIGN COMPONENT 1 OF STRUCTURE <gfs_data> TO FIELD-SYMBOL(<lfs_mandt>).
      IF sy-subrc EQ 0.
        <lfs_mandt> = sy-mandt.
      ENDIF.
      APPEND <gfs_data> TO <gft_data>.
      CLEAR <gfs_data>.
    ENDAT.
    CLEAR lv_i.
  ENDLOOP.
ENDFORM.
*&---------------------------------------------------------------------*
*& Form remove_duplicates
*&---------------------------------------------------------------------*
FORM remove_duplicates .
  DATA: lt_keys TYPE abap_sortorder_tab,
        ls_keys TYPE string.

  CLEAR :lt_keys[],ls_keys.

  lt_keys = VALUE #( BASE lt_keys FOR <lfs_keys> IN gt_tab_fields
  WHERE ( keyflag = abap_true AND fieldname NE |MANDT|  )
  ( name = <lfs_keys>-fieldname ) ).
  ls_keys = REDUCE #( INIT text = || FOR <lfs_key> IN lt_keys
  NEXT text = text && |{ <lfs_key>-name } | ).

*--For the test coverage master database tables, we may have a maximum of 3 primary keys,
*  thus created 3 variables to capture the same.
  SPLIT ls_keys AT space INTO DATA(lv_key1) DATA(lv_key2) DATA(lv_key3).

  SORT <gft_data> BY (lt_keys).
  DELETE ADJACENT DUPLICATES FROM <gft_data> COMPARING (lv_key1) (lv_key2) (lv_key3).
ENDFORM.
*&---------------------------------------------------------------------*
*& Form load_to_db
*&---------------------------------------------------------------------*
FORM load_to_db.
*� Create dynamic work area
  TYPES: ty_scpt TYPE STANDARD TABLE OF /smash/t_scpt.
  DATA: lt_data       TYPE REF TO data,
        ls_data       TYPE REF TO data,
        lv_success(1),
        lv_fail(1).

  FIELD-SYMBOLS: <lfs_table> TYPE any,
                 <lfs_row>   TYPE any,
                 <lft_db>    TYPE STANDARD TABLE.

  CREATE DATA lt_data TYPE TABLE OF (p_table).
  ASSIGN lt_data->* TO <lft_db>.

  CREATE DATA ls_data TYPE (p_table).
  ASSIGN ls_data->* TO <lfs_table>.

  SELECT * FROM (p_table) INTO CORRESPONDING FIELDS OF TABLE @<lft_db>.

  SET UPDATE TASK LOCAL.

  LOOP AT <gft_data> ASSIGNING FIELD-SYMBOL(<lfs_data>).
    CLEAR <lfs_table>.
*    <lfs_table> = CORRESPONDING #( <lfs_data> ).
    MOVE-CORRESPONDING <lfs_data> TO <lfs_table>.
    CASE p_table.
      WHEN '*ZTABLE1*'.
        ASSIGN COMPONENT |*KEY_FIELD_1*| OF STRUCTURE <lfs_data> TO FIELD-SYMBOL(<lv_table1_key_field_1>).
        ASSIGN COMPONENT |*KEY_FIELD_2*| OF STRUCTURE <lfs_data> TO FIELD-SYMBOL(<lv_table1_key_field_2>).
        ASSIGN COMPONENT |*KEY_FIELD_3*| OF STRUCTURE <lfs_data> TO FIELD-SYMBOL(<lv_table1_key_field_3>).
        READ TABLE <lft_db> ASSIGNING <lfs_row> WITH KEY ('*KEY_FIELD_1*') = <lv_table1_key_field_1>
                                                         ('*KEY_FIELD_2*') = <lv_table1_key_field_2>
                                                         ('*KEY_FIELD_3*') = <lv_table1_key_field_3> BINARY SEARCH.
      WHEN '*ZTABLE2*'.
        ASSIGN COMPONENT |*KEY_FIELD_1*| OF STRUCTURE <lfs_data> TO FIELD-SYMBOL(<lv_table2_key_field_1>).
        ASSIGN COMPONENT |*KEY_FIELD_2*| OF STRUCTURE <lfs_data> TO FIELD-SYMBOL(<lv_table2_key_field_2>).
        ASSIGN COMPONENT |*KEY_FIELD_3*| OF STRUCTURE <lfs_data> TO FIELD-SYMBOL(<lv_table2_key_field_3>).
        READ TABLE <lft_db> ASSIGNING <lfs_row> WITH KEY ('*KEY_FIELD_1*') = <lv_table2_key_field_1>
                                                         ('*KEY_FIELD_2*') = <lv_table2_key_field_2>
                                                         ('*KEY_FIELD_3*') = <lv_table2_key_field_3> BINARY SEARCH.
      WHEN '*ZTABLE3*'.
        ASSIGN COMPONENT |*KEY_FIELD_1*| OF STRUCTURE <lfs_data> TO FIELD-SYMBOL(<lv_table3_key_field_1>).
        ASSIGN COMPONENT |*KEY_FIELD_2*| OF STRUCTURE <lfs_data> TO FIELD-SYMBOL(<lv_table3_key_field_2>).
        ASSIGN COMPONENT |*KEY_FIELD_3*| OF STRUCTURE <lfs_data> TO FIELD-SYMBOL(<lv_table3_key_field_3>).
      READ TABLE <lft_db> ASSIGNING <lfs_row> WITH KEY ('*KEY_FIELD_1*') = <lv_table3_key_field_1>
                                                       ('*KEY_FIELD_2*') = <lv_table3_key_field_2>
                                                       ('*KEY_FIELD_3*') = <lv_table3_key_field_3> BINARY SEARCH.
      WHEN '*ZTABLE4*'.
      ASSIGN COMPONENT |*KEY_FIELD_1*| OF STRUCTURE <lfs_data> TO FIELD-SYMBOL(<lv_table4_key_field_1>).
      ASSIGN COMPONENT |*KEY_FIELD_2*| OF STRUCTURE <lfs_data> TO FIELD-SYMBOL(<lv_table4_key_field_2>).
      ASSIGN COMPONENT |*KEY_FIELD_3*| OF STRUCTURE <lfs_data> TO FIELD-SYMBOL(<lv_table4_key_field_3>).
      READ TABLE <lft_db> ASSIGNING <lfs_row> WITH KEY ('*KEY_FIELD_1*') = <lv_table4_key_field_1>
                                                       ('*KEY_FIELD_2*') = <lv_table4_key_field_2>
                                                       ('*KEY_FIELD_3*') = <lv_table4_key_field_3> BINARY SEARCH.
      WHEN '*ZTABLE5*'.
      ASSIGN COMPONENT |*KEY_FIELD_1*| OF STRUCTURE <lfs_data> TO FIELD-SYMBOL(<lv_table5_key_field_1>).
      ASSIGN COMPONENT |*KEY_FIELD_2*| OF STRUCTURE <lfs_data> TO FIELD-SYMBOL(<lv_table5_key_field_2>).
      ASSIGN COMPONENT |*KEY_FIELD_3*| OF STRUCTURE <lfs_data> TO FIELD-SYMBOL(<lv_table5_key_field_3>).
      READ TABLE <lft_db> ASSIGNING <lfs_row> WITH KEY ('*KEY_FIELD_1*') = <lv_table5_key_field_1>
                                                       ('*KEY_FIELD_2*') = <lv_table5_key_field_2>
                                                       ('*KEY_FIELD_3*') = <lv_table5_key_field_3> BINARY SEARCH.
    ENDCASE.
    IF <lfs_row> IS ASSIGNED.
      ASSIGN COMPONENT |UPDATED_BY| OF STRUCTURE <lfs_table> TO FIELD-SYMBOL(<lfs_updt_by>).
      IF sy-subrc EQ 0.
        <lfs_updt_by> = sy-uname.
      ENDIF.
      ASSIGN COMPONENT |UPDATED_ON| OF STRUCTURE <lfs_table> TO FIELD-SYMBOL(<lfs_updt_on>).
      IF sy-subrc EQ 0.
        <lfs_updt_on> = sy-datum.
      ENDIF.
      ASSIGN COMPONENT |CREATED_BY| OF STRUCTURE <lfs_table> TO FIELD-SYMBOL(<lfs_ins_by>).
      ASSIGN COMPONENT |CREATED_BY| OF STRUCTURE <lfs_row> TO FIELD-SYMBOL(<lfs_row_by>).
      IF sy-subrc EQ 0.
        <lfs_ins_by> = <lfs_row_by>.
      ENDIF.
      ASSIGN COMPONENT |CREATED_ON| OF STRUCTURE <lfs_table> TO FIELD-SYMBOL(<lfs_ins_on>).
      ASSIGN COMPONENT |CREATED_ON| OF STRUCTURE <lfs_row> TO FIELD-SYMBOL(<lfs_row_on>).
      IF sy-subrc EQ 0.
        <lfs_ins_on> = <lfs_row_on>.
      ENDIF.
      UPDATE (p_table)  FROM <lfs_table>.
      IF sy-subrc EQ 0.
        gv_success = gv_success + 1.
        lv_success = abap_true.
      ELSE.
        gv_error = gv_error + 1.
        lv_fail = abap_true.
      ENDIF.
    ELSE.
      ASSIGN COMPONENT |CREATED_BY| OF STRUCTURE <lfs_table> TO FIELD-SYMBOL(<lfs_ins_by1>).
      IF sy-subrc EQ 0.
        <lfs_ins_by1> = sy-uname.
      ENDIF.
      ASSIGN COMPONENT |CREATED_ON| OF STRUCTURE <lfs_table> TO FIELD-SYMBOL(<lfs_ins_on1>).
      IF sy-subrc EQ 0.
        <lfs_ins_on1> = sy-datum.
      ENDIF.
      INSERT INTO (p_table)  VALUES <lfs_table>.
      IF sy-subrc EQ 0.
        gv_success = gv_success + 1.
        lv_success = abap_true.
      ELSE.
        gv_error = gv_error + 1.
        lv_fail = abap_true.
      ENDIF.
    ENDIF.
    MOVE-CORRESPONDING <lfs_table> TO <lfs_data>.
    IF lv_success IS NOT INITIAL.
      ASSIGN COMPONENT |STATUS| OF STRUCTURE <lfs_data> TO FIELD-SYMBOL(<lfs_success>).
      IF sy-subrc EQ 0.
        <lfs_success> = |@08@|.
      ENDIF.
    ELSEIF lv_fail IS NOT INITIAL.
      ASSIGN COMPONENT |STATUS| OF STRUCTURE <lfs_data> TO FIELD-SYMBOL(<lfs_fail>).
      IF sy-subrc EQ 0.
        <lfs_fail> = |@0A@|.
      ENDIF.
    ENDIF.
    CLEAR: lv_success,lv_fail.
  ENDLOOP.
ENDFORM.
*&---------------------------------------------------------------------*
*& Form create_dyn_Table
*&---------------------------------------------------------------------*
FORM create_dyn_table.
  CLEAR : go_strucdescr,gt_tab_fields[].

  go_strucdescr ?= cl_abap_elemdescr=>describe_by_name( p_table ).

  gt_tab_fields = go_strucdescr->get_ddic_field_list( ).

  gt_fcat = VALUE #( BASE gt_fcat FOR <lfs_fields> IN gt_tab_fields ( CORRESPONDING #( <lfs_fields> ) ) ).

*--Additional Column to capture the status of upload
  gt_fcat = VALUE #( BASE gt_fcat ( fieldname  = |STATUS|
  datatype   = |CHAR_17|
  inttype    = |CHAR_17|
  intlen     = |10|
  scrtext_s  = |Status|
  scrtext_m  = |Status|
  scrtext_l  = |Status|  ) ).

  CALL METHOD cl_alv_table_create=>create_dynamic_table
    EXPORTING
      it_fieldcatalog = gt_fcat
    IMPORTING
      ep_table        = gt_dyn_data.
  ASSIGN gt_dyn_data->* TO <gft_data>.
  CREATE DATA gs_dyn_data LIKE LINE OF <gft_data>.
  ASSIGN gs_dyn_data->* TO <gfs_data>.
ENDFORM.
*&---------------------------------------------------------------------*
*& Form display_result
*&---------------------------------------------------------------------*
FORM display_result .
*�-Create Instance
  TRY.
      CALL METHOD cl_salv_table=>factory
        IMPORTING
          r_salv_table = gr_table
        CHANGING
          t_table      = <gft_data>.
    CATCH cx_salv_msg. " ALV: General Error Class with Message
  ENDTRY.

*--Toolbar funtion
  gr_functions = gr_table->get_functions( ).
  gr_functions->set_all( abap_true ).

*--Optimize Cols
  go_cols =   gr_table->get_columns( ).
  go_cols->set_optimize( ).

*--Set Col Names
  LOOP AT gt_fcat ASSIGNING FIELD-SYMBOL(<lfs_fcat>).
    TRY .
        DATA(lo_col) = go_cols->get_column( <lfs_fcat>-fieldname ).
        lo_col->set_short_text( <lfs_fcat>-scrtext_s  ).
        lo_col->set_medium_text( <lfs_fcat>-scrtext_m  ).
        lo_col->set_long_text( <lfs_fcat>-scrtext_l ).
      CATCH cx_salv_not_found.
    ENDTRY.
  ENDLOOP.

*--Header
  CREATE OBJECT go_header.
  go_header->create_label( EXPORTING row    = 1
                                     column = 1
                                     text   = |NO. OF records successfully uploaded| && | : { gv_success }| ).

  go_header->create_label( EXPORTING row    = 2
                                     column = 1
                                     text   = |NO. OF records unable TO upload| && | : { gv_error }| ).

  gr_table->set_top_of_list( go_header  ).
  gr_table->set_top_of_list_print( go_header ).

*--Display ALV \Output
  gr_table->display( ).
ENDFORM.
