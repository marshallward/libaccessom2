module accessom2_mod

use, intrinsic :: iso_c_binding, only: c_null_char
use datetime_module, only : datetime, c_strptime, tm2date, tm_struct, timedelta
use error_handler, only : assert

implicit none
private
public accessom2

type accessom2
    private

    ! Intercommunicators
    integer :: ice_intercomm, ocean_intercomm

    character(len=6) :: model_name, calendar

    type(datetime) :: start_date
    type(datetime) :: end_date
    type(datetime) :: job_end_date

contains
    private
    procedure, pass(self), public :: init => accessom2_init
    procedure, pass(self), public :: deinit => accessom2_deinit
    procedure, pass(self), public :: get_start_date
    procedure, pass(self), public :: get_end_date
endtype accessom2

character(len=19) :: start_date, end_date
character(len=6) :: calendar
integer, dimension(3) :: job_runtime
character(len=19) :: current_datetime
 
namelist /accessom2_nml/ start_date, end_date, calendar, job_runtime
namelist /do_not_edit_nml/ current_datetime

contains

subroutine accessom2_init(self, model_name)
    class(accessom2), intent(inout) :: self
    character(len=6), intent(in) :: model_name

    type(tm_struct) :: ctime
    logical :: file_exists
    integer :: tmp_unit, rc

    self%model_name = model_name

    ! Read namelist which includes information about the start and end date
    inquire(file='accessom2.nml', exist=file_exists)
    call assert(file_exists, 'Input accessom2.nml does not exist.')
    open(newunit=tmp_unit, file='accessom2.nml')
    read(tmp_unit, nml=accessom2_nml)
    close(tmp_unit)

    inquire(file='accessom2_datetime.nml', exist=file_exists)
    if (file_exists) then
        open(newunit=tmp_unit, file='accessom2_datetime.nml')
        read(tmp_unit, nml=do_not_edit_nml)
        close(tmp_unit)
        rc = c_strptime(current_datetime//c_null_char, &
                        "%Y-%m-%dT%H:%M:%S"//c_null_char, ctime)
        call assert(rc /= 0, 'Bad start_date format in accessom2_datetime.nml')
        self%start_date = tm2date(ctime)
    else
        rc = c_strptime(start_date//c_null_char, &
                        "%Y-%m-%dT%H:%M:%S"//c_null_char, ctime)
        call assert(rc /= 0, 'Bad start_date format in accessom2.nml')
        self%start_date = tm2date(ctime)
    endif

    rc = c_strptime(end_date//c_null_char, &
                    "%Y-%m-%dT%H:%M:%S"//c_null_char, ctime)
    call assert(rc /= 0, 'Bad end_date format in accessom2.nml')
    self%end_date = tm2date(ctime)

    self%calendar = calendar
    self%job_end_date = job_end_date(self%start_date, job_runtime, &
                                     self%end_date, calendar)
    if (self%end_date < self%job_end_date) then
        self%job_end_date = self%end_date
    endif

endsubroutine accessom2_init

function get_start_date(self)
    class(accessom2), intent(inout) :: self
    type(datetime) :: get_start_date

    get_start_date = self%start_date

endfunction get_start_date

function get_end_date(self)
    class(accessom2), intent(inout) :: self
    type(datetime) :: get_end_date

    get_end_date = self%job_end_date

endfunction get_end_date


!> Called by all models at the end of the run.
! The root will write out the new current date
subroutine accessom2_deinit(self, cur_date)
    class(accessom2), intent(inout) :: self
    type(datetime), intent(in) :: cur_date

    integer :: tmp_unit, my_pe, err
    integer, dimension(1) :: buf

    current_datetime = cur_date%strftime('%Y-%m-%dT%H:%M:%S')

    if (self%model_name == 'matmxx') then
        open(newunit=tmp_unit, file='accessom2_datetime.nml')
        write(unit=tmp_unit, nml=do_not_edit_nml)
        close(tmp_unit)
    endif

endsubroutine accessom2_deinit

function job_end_date(start_date, job_runtime, end_date, calendar)
    type(datetime), intent(in) :: start_date, end_date
    integer, dimension(3), intent(in) :: job_runtime
    character(len=6), intent(in) :: calendar

    type(datetime) :: job_end_date
    integer :: year, month, day, hour, minute, second, i

    if (job_runtime(3) > 0) then
        call assert(job_runtime(1) == 0 .and. job_runtime(2) == 0, &
                    'Job runtime must be only one of years, months, seconds')

        day = start_date%getDay()
        hour = start_date%getHour()
        minute = start_date%getMinute()
        second = start_date%getSecond()

        second = second + job_runtime(3)
        if (second > 0) then
            minute = minute + (second / 60)
            second = mod(second, 60)
        endif
        if (minute > 0) then
            hour = hour + (minute / 60)
            minute = mod(minute, 60)
        endif
        if (hour > 0) then
            day = day + (hour / 24)
            hour = mod(hour, 24)
        endif

        job_end_date = datetime(start_date%getYear(), start_date%getMonth(), 1, &
                                hour, minute, second)
        do i=1, day-1
            if (job_end_date%getMonth() == 2 .and. job_end_date%getDay() == 29 &
                .and. calendar == 'noleap')  then
                job_end_date = job_end_date + timedelta(days=1)
            endif
            job_end_date = job_end_date + timedelta(days=1)
        enddo

    elseif (job_runtime(2) > 0) then
        call assert(job_runtime(1) == 0 .and. job_runtime(3) == 0, &
                    'Job runtime must be only one of years, months, seconds')

        year = start_date%getYear()
        month = start_date%getMonth() + job_runtime(2)
        year = year + (month / 12)
        month = mod(month, 12)

        job_end_date = datetime(year, month, start_date%getDay(), &
                                start_date%getHour(), start_date%getMinute(), &
                                start_date%getSecond())

    elseif (job_runtime(1) > 0) then
        call assert(job_runtime(2) == 0 .and. job_runtime(3) == 0, &
                    'Job runtime must be only one of years, months, seconds')

        year = start_date%getYear() + job_runtime(1)
        job_end_date = datetime(year, start_date%getMonth(), start_date%getDay(), &
                                start_date%getHour(), start_date%getMinute(), &
                                start_date%getSecond())
    endif
endfunction job_end_date

endmodule accessom2_mod