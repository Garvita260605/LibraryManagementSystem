/* 
  Table 1: For USERS

  Purpose: To Store user login information and role.
  Roles supported: Student, Teacher, Library Staff
*/

CREATE TABLE USERS (
    USER_ID NUMBER PRIMARY KEY,
    NAME VARCHAR2(100),
    EMAIL VARCHAR2(100) UNIQUE,
    ROLE VARCHAR2(20) CHECK (ROLE IN ('Student', 'Teacher', 'Staff'))
);

/*

  Table 2: For BOOKS

  Purpose: Stores the details of all books in the 
           library including ID, Title, and Author.
*/

CREATE TABLE BOOKS (
    BOOK_ID NUMBER PRIMARY KEY,
    TITLE VARCHAR2(150),
    AUTHOR VARCHAR2(100)
);

/*

  Table 3: ISSUE_RECORDS

  Purpose: Stores record of each book issued:
           - who issued it
           - which book was issued
           - when it was issued
           - when it's due
           - when it's returned (optional)
           - fine (calculated on return if overdue)
*/
CREATE TABLE ISSUE_RECORDS (
    RECORD_ID NUMBER PRIMARY KEY,
    USER_ID NUMBER REFERENCES USERS(USER_ID),
    BOOK_ID NUMBER REFERENCES BOOKS(BOOK_ID),
    ISSUE_DATE DATE DEFAULT SYSDATE,
    DUE_DATE DATE,
    RETURN_DATE DATE,
    FINE NUMBER DEFAULT 0
);

/*

  Table 4: TEMP_OTP
  Purpose: Used to simulate OTP-based login.

           Stores the latest OTP generated for each user.

*/
CREATE TABLE TEMP_OTP (
    USER_ID NUMBER REFERENCES USERS(USER_ID),
    OTP_CODE VARCHAR2(6),
    GENERATED_AT TIMESTAMP DEFAULT SYSTIMESTAMP
);

/*

  Function: GET_DUE_DATE

  Input : ROLE (Student / Teacher / Staff)
  Output: Calculated Due Date (SYSDATE + X days)
  Logic :
      - Student => Issued for 14 days
      - Teacher => Issued for 180 days
      - Staff   => Issued for 270 days

*/

CREATE OR REPLACE FUNCTION GET_DUE_DATE(USER_ROLE IN VARCHAR2)
RETURN DATE
IS
    v_due_date DATE;
BEGIN
    CASE USER_ROLE
        WHEN 'Student' THEN
            v_due_date := SYSDATE + 14;
        WHEN 'Teacher' THEN
            v_due_date := SYSDATE + 180;
        WHEN 'Staff' THEN
            v_due_date := SYSDATE + 270;
        ELSE
            RAISE_APPLICATION_ERROR(-20001, 'Invalid Role');
    END CASE;

    RETURN v_due_date;
END;
/

/*
  Procedure: ISSUE_BOOK

  Purpose:
    - Issues a book to a user
    - Calculates due date using GET_DUE_DATE()
    - Inserts record into ISSUE_RECORDS table

  Inputs:
    - p_user_id: ID of the user issuing the book
    - p_book_id: ID of the book being issued
*/

CREATE OR REPLACE PROCEDURE ISSUE_BOOK (
    p_user_id IN NUMBER,
    p_book_id IN NUMBER
)
IS
    v_role USERS.ROLE%TYPE;
    v_due_date DATE;
    v_record_id NUMBER;
BEGIN
    -- 1. Will Get user role
    SELECT ROLE INTO v_role
    FROM USERS
    WHERE USER_ID = p_user_id;

    -- 2. Will Get due date based on role
    v_due_date := GET_DUE_DATE(v_role);

    -- 3. Will Generate new record ID (using sequence or MAX logic)
    SELECT NVL(MAX(RECORD_ID), 0) + 1 INTO v_record_id FROM ISSUE_RECORDS;

    -- 4. Will Insert issue record
    INSERT INTO ISSUE_RECORDS (
        RECORD_ID, USER_ID, BOOK_ID, ISSUE_DATE, DUE_DATE
    )
    VALUES (
        v_record_id, p_user_id, p_book_id, SYSDATE, v_due_date
    );

    DBMS_OUTPUT.PUT_LINE('Book issued successfully. Due date is: ' || TO_CHAR(v_due_date, 'DD-MON-YYYY'));

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('User not found.');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/

/*

  Function: CALCULATE_FINE

  Purpose: Calculates fine based on return delay
  Inputs: p_due_date, p_return_date
  Output: Fine amount (₹10 per delayed day for everyone)
*/

CREATE OR REPLACE FUNCTION CALCULATE_FINE (
    p_due_date DATE,
    p_return_date DATE
) RETURN NUMBER
IS
    v_fine NUMBER := 0;
    v_delay NUMBER;
BEGIN
    IF p_return_date > p_due_date THEN
        v_delay := p_return_date - p_due_date;
        v_fine := v_delay * 10;
    END IF;
    RETURN v_fine;
END;
/

/*
  Trigger: TRG_CALCULATE_FINE

  Purpose: Automatically calculates fine after return_date update
  Logic:
    - Checks if RETURN_DATE is set
    - Calls CALCULATE_FINE function
    - Updates FINE column accordingly
*/

CREATE OR REPLACE TRIGGER TRG_CALCULATE_FINE
BEFORE UPDATE OF RETURN_DATE ON ISSUE_RECORDS
FOR EACH ROW
WHEN (NEW.RETURN_DATE IS NOT NULL)
BEGIN
    -- Assign fine directly to the new row being updated
    :NEW.FINE := CALCULATE_FINE(:OLD.DUE_DATE, :NEW.RETURN_DATE);
END;
/

/*
  Procedure: RETURN_BOOK

  Purpose:
    - Sets RETURN_DATE in ISSUE_RECORDS
    - Fine will be auto-updated via trigger
*/

CREATE OR REPLACE PROCEDURE RETURN_BOOK (
    p_record_id IN NUMBER,
    p_return_date IN DATE
)
IS
BEGIN
    UPDATE ISSUE_RECORDS
    SET RETURN_DATE = p_return_date
    WHERE RECORD_ID = p_record_id;

    DBMS_OUTPUT.PUT_LINE('Book returned successfully.');
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Record not found.');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/

/*
  ======================================================
  Table: TEMP_OTP
  ------------------------------------------------------
  Stores simulated OTPs for each user, valid for short time.
  ======================================================
*/
CREATE TABLE TEMP_OTP (
    USER_ID NUMBER REFERENCES USERS(USER_ID),
    OTP_CODE VARCHAR2(6),
    GENERATED_AT TIMESTAMP DEFAULT SYSTIMESTAMP
);
/*
  Procedure: GENERATE_OTP

  Purpose:
    - Simulates OTP generation for a user
    - Stores the OTP in TEMP_OTP table
*/

CREATE OR REPLACE PROCEDURE GENERATE_OTP (
    p_user_id IN NUMBER
)
IS
    v_otp VARCHAR2(6);
BEGIN
    -- Generate a random 6-digit OTP
    v_otp := TO_CHAR(TRUNC(DBMS_RANDOM.VALUE(100000, 999999)));

    -- Remove existing OTP if any
    DELETE FROM TEMP_OTP WHERE USER_ID = p_user_id;

    -- Insert new OTP
    INSERT INTO TEMP_OTP (USER_ID, OTP_CODE, GENERATED_AT)
    VALUES (p_user_id, v_otp, SYSTIMESTAMP);

    DBMS_OUTPUT.PUT_LINE('OTP generated for USER_ID ' || p_user_id || ': ' || v_otp);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/
/*
  Procedure: VERIFY_OTP
  Purpose:
    - Accepts user ID and OTP input
    - Checks if OTP is correct and recent (within 5 mins)
*/

CREATE OR REPLACE PROCEDURE VERIFY_OTP (
    p_user_id IN NUMBER,
    p_entered_otp IN VARCHAR2
)
IS
    v_real_otp VARCHAR2(6);
    v_generated_at TIMESTAMP;
BEGIN
    SELECT OTP_CODE, GENERATED_AT
    INTO v_real_otp, v_generated_at
    FROM TEMP_OTP
    WHERE USER_ID = p_user_id;

    IF v_real_otp = p_entered_otp THEN
        IF SYSTIMESTAMP - v_generated_at < INTERVAL '5' MINUTE THEN
            DBMS_OUTPUT.PUT_LINE('✅ OTP Verified! Login successful.');
        ELSE
            DBMS_OUTPUT.PUT_LINE('❌ OTP expired. Please request a new one.');
        END IF;
    ELSE
        DBMS_OUTPUT.PUT_LINE('❌ Incorrect OTP.');
    END IF;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('❌ No OTP found for this user.');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/

-- USERS
INSERT INTO USERS VALUES (1, 'Ravi Kumar', 'ravi@student.com', 'Student');
INSERT INTO USERS VALUES (2, 'Dr. Mehta', 'mehta@teacher.com', 'Teacher');
INSERT INTO USERS VALUES (3, 'Neha Joshi', 'neha@staff.com', 'Staff');

-- BOOKS
INSERT INTO BOOKS VALUES (101, 'Introduction to PL/SQL', 'John Smith');
INSERT INTO BOOKS VALUES (102, 'Database Systems', 'Elmasri & Navathe');


-- Now its time to check and implement the project
EXEC ISSUE_BOOK(1, 101); --Whenever it's needed to issue a book 
EXEC RETURN_BOOK(1, SYSDATE); -- To return a book
SELECT * FROM ISSUE_RECORDS WHERE RECORD_ID = 1; --To confirm the details of the person who returned the book
EXEC GENERATE_OTP(1); -- Ravi (Student)
EXEC VERIFY_OTP(1, 123456); -- It will verify OTP and it will 


--It will nullify ur records..
DELETE FROM ISSUE_RECORDS
WHERE RECORD_ID = 1;
COMMIT;


--Let's try to create OTP..
BEGIN 
    GENERATE_OTP(1); 
END;
/
EXEC VERIFY_OTP(1, '843789'); -- Verified the OTP..