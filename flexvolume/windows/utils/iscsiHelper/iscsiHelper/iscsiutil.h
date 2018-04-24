#pragma once

#define RETURN_ERROR( err ) return

#define RETURN_ON_ERROR( err )     \
    {                              \
        if( err != ERROR_SUCCESS ) \
            RETURN_ERROR( err );   \
    }

DWORD EnsureError(DWORD err)
{
    if (err != 0)
        return err;
    return 1;
}


typedef struct _STORAGE_DEVICE_UNIQUE_IDENTIFIER
{
    ULONG Version;
    ULONG Size;
    ULONG StorageDeviceIdOffset;
    ULONG StorageDeviceOffset;
    ULONG DriveLayoutSignatureOffset;
} STORAGE_DEVICE_UNIQUE_IDENTIFIER, *PSTORAGE_DEVICE_UNIQUE_IDENTIFIER;

typedef struct _HELP_PERSISTENT_RESERVE_COMMAND
{
    ULONGLONG                  Padding;
    PRO_PARAMETER_LIST         Param;
    PERSISTENT_RESERVE_COMMAND PrCommand;
} HELP_PERSISTENT_RESERVE_COMMAND, *PHELP_PERSISTENT_RESERVE_COMMAND;

struct Reservation
{
    ULONGLONG key;
    DWORD     address;
    USHORT    type;
    USHORT    scope;

    static std::vector<Reservation> Construct(PRI_RESERVATION_LIST * list)
    {
        DWORD size;
        REVERSE_BYTES(&size, &list->AdditionalLength);
        DWORD elements = size / sizeof(PRI_RESERVATION_DESCRIPTOR);

        std::vector<Reservation> keyArray(elements);
        for (DWORD i = 0; i < elements; ++i)
        {
            PRI_RESERVATION_DESCRIPTOR & descriptor = list->Reservations[i];

            REVERSE_BYTES_QUAD(&keyArray[i].key, &descriptor.ReservationKey);
            REVERSE_BYTES(&keyArray[i].address, &descriptor.ScopeSpecificAddress);
            keyArray[i].type = descriptor.Type;
            keyArray[i].scope = descriptor.Scope;
        }
        return keyArray;
    }
};

template<typename T, typename ErrorType = DWORD>
class ErrorAndResult : public std::variant<T, ErrorType>
{
public:
    ErrorAndResult(ErrorAndResult && rhs) = default;
    static ErrorAndResult error(ErrorType errorValue)
    {
        return ErrorAndResult(std::in_place_index_t<1>(), errorValue);
    }

    template<typename... Tx>
    static ErrorAndResult result(Tx &&... vx)
    {
        return ErrorAndResult(std::in_place_index_t<0>(), std::forward<Tx>(vx)...);
    }
    using std::variant<T, ErrorType>::variant;

    bool IsError() const
    {
        return std::get_if<1>(this) != nullptr;
    }

    const T & GetValue() const
    {
        return std::get<0>(*this);
    }

    T & GetValue()
    {
        return std::get<0>(*this);
    }

    ErrorType GetError() const
    {
        return std::get<1>(*this);
    }
};

template<typename T>
class TypedBuffer : public std::vector<BYTE>
{
public:
    using std::vector<BYTE>::vector;
    T * GetPtr()
    {
        return (T *)data();
    }
};

ErrorAndResult<std::vector<Reservation>>
ReadReservations(
    _In_ HANDLE Device)
    /*++

    Routine Description:

    This routine reads persistent reservation keys from LUN.

    Arguments:

    Device - Lun device handle with R/W access.

    RegistrationList - Double pointer to receive the buffer contains PR key list.
    Caller is expected to free the buffer upon success.

    Return Value:

    WIN32 error.

    --*/
{
    HELP_PERSISTENT_RESERVE_COMMAND   rserverCommand = { 0 };
    PPERSISTENT_RESERVE_COMMAND       param = (PPERSISTENT_RESERVE_COMMAND)&rserverCommand;
    ULONG                             returnedBytes = 0;
    ULONG                             keyCount = 0;
    ULONGLONG                         key = 30; // for first call hold space for 30 keys
    TypedBuffer<PRI_RESERVATION_LIST> RegistrationList;

    param->Version = sizeof(PERSISTENT_RESERVE_COMMAND);
    param->Size = sizeof(rserverCommand);
    param->PR_IN.ServiceAction = RESERVATION_ACTION_READ_RESERVATIONS;

    do
    {
        RegistrationList.resize(keyCount * sizeof(PRI_RESERVATION_DESCRIPTOR) + sizeof(PRI_RESERVATION_LIST));
        param->PR_IN.AllocationLength = (USHORT)RegistrationList.size();
        if (!DeviceIoControl(Device,
            IOCTL_STORAGE_PERSISTENT_RESERVE_IN,
            param,
            param->Size,
            RegistrationList.data(),
            param->PR_IN.AllocationLength,
            &returnedBytes,
            NULL))
        {
            DWORD status = GetLastError();
            if (status != ERROR_MORE_DATA)
            {
                return status;
            }
            RegistrationList.resize(returnedBytes);
            param->PR_IN.AllocationLength = (USHORT)RegistrationList.size();
            if (!DeviceIoControl(Device,
                IOCTL_STORAGE_PERSISTENT_RESERVE_IN,
                param,
                param->Size,
                RegistrationList.data(),
                param->PR_IN.AllocationLength,
                &returnedBytes,
                NULL))
            {
                status = GetLastError();
                return status;
            }
        }
        REVERSE_BYTES(&keyCount, &RegistrationList.GetPtr()->AdditionalLength);
        keyCount = keyCount / sizeof(PRI_RESERVATION_DESCRIPTOR);
    } while (keyCount * sizeof(PRI_RESERVATION_DESCRIPTOR) + sizeof(PRI_RESERVATION_LIST) > RegistrationList.size());

    return Reservation::Construct(RegistrationList.GetPtr());
}

DWORD
GetCacheInfo(
    HANDLE DeviceHandle)
{
    DWORD                  status = ERROR_SUCCESS;
    DWORD                  bytesReturned;
    DISK_CACHE_INFORMATION CacheInfo = { 0 };

    if (!DeviceIoControl(DeviceHandle,
        IOCTL_DISK_GET_CACHE_INFORMATION,
        NULL,
        0,
        &CacheInfo,
        sizeof(DISK_CACHE_INFORMATION),
        &bytesReturned,
        NULL))
    {
        status = GetLastError();
        status = EnsureError(status);
    }

    return status;
}

DWORD
PRRegisterKeyNoCacheInfo(
    HANDLE    DeviceHandle,
    ULONGLONG Key)
{
    DWORD                           status = ERROR_SUCCESS;
    HELP_PERSISTENT_RESERVE_COMMAND Param = { 0 };
    PPERSISTENT_RESERVE_COMMAND     param = (PPERSISTENT_RESERVE_COMMAND)&Param;
    PPRO_PARAMETER_LIST             ppro;
    DWORD                           bytesReturned;

    RtlZeroMemory(&Param, sizeof(Param));

    param->Version = sizeof(PERSISTENT_RESERVE_COMMAND);
    param->Size = sizeof(Param);
    param->PR_OUT.ServiceAction = RESERVATION_ACTION_REGISTER_IGNORE_EXISTING;
    ppro = (PPRO_PARAMETER_LIST)param->PR_OUT.ParameterList;
    REVERSE_BYTES_QUAD(&(ppro->ServiceActionReservationKey), &Key);

    if (!DeviceIoControl(DeviceHandle,
        IOCTL_STORAGE_PERSISTENT_RESERVE_OUT,
        param,
        param->Size,
        NULL,
        0,
        &bytesReturned,
        NULL))
    {
        status = GetLastError();
        status = EnsureError(status);
    }

    return status;
}

DWORD
PRRegisterKey(
    HANDLE    DeviceHandle,
    ULONGLONG Key)
{
    DWORD status = PRRegisterKeyNoCacheInfo(DeviceHandle, Key);

    if (status == ERROR_SUCCESS)
    {
        GetCacheInfo(DeviceHandle);
    }

    return status;
}

std::vector<ULONGLONG>
SpClCreatePRKeyArray(
    __in PPRI_REGISTRATION_LIST RegList)
{
    DWORD size;
    REVERSE_BYTES(&size, &RegList->AdditionalLength);
    DWORD elements = size / sizeof(ULONGLONG);

    std::vector<ULONGLONG> KeyArray(elements);

    for (DWORD ndx = 0; ndx < elements; ndx++)
    {
        REVERSE_BYTES_QUAD(&KeyArray[ndx], &(RegList->ReservationKeyList[ndx]));
    }
    return KeyArray;
}

ErrorAndResult<std::vector<ULONGLONG>>
ReadKeys(
    _In_ HANDLE Device)
    /*++

    Routine Description:

    This routine reads persistent reservation keys from LUN.

    Arguments:

    Device - Lun device handle with R/W access.

    RegistrationList - Double pointer to receive the buffer contains PR key list.
    Caller is expected to free the buffer upon success.

    Return Value:

    WIN32 error.

    --*/
{
    HELP_PERSISTENT_RESERVE_COMMAND    rserverCommand = { 0 };
    PPERSISTENT_RESERVE_COMMAND        param = (PPERSISTENT_RESERVE_COMMAND)&rserverCommand;
    ULONG                              returnedBytes = 0;
    ULONG                              keyCount = 0;
    ULONGLONG                          key = 30; // for first call hold space for 30 keys
    TypedBuffer<PRI_REGISTRATION_LIST> RegistrationList;

    param->Version = sizeof(PERSISTENT_RESERVE_COMMAND);
    param->Size = sizeof(rserverCommand);
    param->PR_IN.ServiceAction = RESERVATION_ACTION_READ_KEYS;

    do
    {
        RegistrationList.resize(keyCount * sizeof(ULONGLONG) + sizeof(PRI_REGISTRATION_LIST));
        param->PR_IN.AllocationLength = (USHORT)RegistrationList.size();
        if (!DeviceIoControl(Device,
            IOCTL_STORAGE_PERSISTENT_RESERVE_IN,
            param,
            param->Size,
            RegistrationList.data(),
            param->PR_IN.AllocationLength,
            &returnedBytes,
            NULL))
        {
            DWORD status = GetLastError();
            if (status != ERROR_MORE_DATA)
            {
                return EnsureError(status);
            }
            RegistrationList.resize(returnedBytes);
            param->PR_IN.AllocationLength = (USHORT)RegistrationList.size();
            if (!DeviceIoControl(Device,
                IOCTL_STORAGE_PERSISTENT_RESERVE_IN,
                param,
                param->Size,
                RegistrationList.data(),
                param->PR_IN.AllocationLength,
                &returnedBytes,
                NULL))
            {
                status = GetLastError();
                return EnsureError(status);
            }
        }
        REVERSE_BYTES(&keyCount, &RegistrationList.GetPtr()->AdditionalLength);
        keyCount = keyCount / sizeof(ULONGLONG);
    } while (keyCount * sizeof(ULONGLONG) + sizeof(PRI_REGISTRATION_LIST) > RegistrationList.size());

    return SpClCreatePRKeyArray(RegistrationList.GetPtr());
}

DWORD
SpClPokeDisk(
    HANDLE DeviceHandle)
{
    PARTITION_INFORMATION_EX partInfo;
    DWORD                    bytes;

    if (!DeviceIoControl(DeviceHandle,
        IOCTL_DISK_UPDATE_PROPERTIES,
        NULL,
        0,
        NULL,
        0,
        &bytes,
        NULL))
    {
        return EnsureError(GetLastError());
    }

    if (!DeviceIoControl(DeviceHandle,
        IOCTL_DISK_GET_PARTITION_INFO_EX,
        NULL,
        0,
        &partInfo,
        sizeof(partInfo),
        &bytes,
        NULL))
    {
        return EnsureError(GetLastError());
    }

    return ERROR_SUCCESS;
}


DWORD
PRUnRegisterKey(
    HANDLE DeviceHandle)
{
    HELP_PERSISTENT_RESERVE_COMMAND Param = { 0 };
    PPERSISTENT_RESERVE_COMMAND     param = (PPERSISTENT_RESERVE_COMMAND)&Param;
    DWORD                           bytesReturned;

    RtlZeroMemory(&Param, sizeof(Param));

    param->Version = sizeof(PERSISTENT_RESERVE_COMMAND);
    param->Size = sizeof(Param);
    param->PR_OUT.ServiceAction = RESERVATION_ACTION_REGISTER_IGNORE_EXISTING;

    if (!DeviceIoControl(DeviceHandle,
        IOCTL_STORAGE_PERSISTENT_RESERVE_OUT,
        param,
        param->Size,
        NULL,
        0,
        &bytesReturned,
        NULL))
    {
        return EnsureError(GetLastError());
    }
    return ERROR_SUCCESS;
}


DWORD
PRReleaseKey(
    HANDLE    DeviceHandle,
    ULONGLONG Key,
    DWORD     scope,
    DWORD     type)
{
    HELP_PERSISTENT_RESERVE_COMMAND Param = { 0 };
    PPERSISTENT_RESERVE_COMMAND     param = (PPERSISTENT_RESERVE_COMMAND)&Param;
    PPRO_PARAMETER_LIST             ppro;
    DWORD                           bytesReturned;

    RtlZeroMemory(&Param, sizeof(Param));

    param->Version = sizeof(PERSISTENT_RESERVE_COMMAND);
    param->Size = sizeof(Param);
    param->PR_OUT.ServiceAction = RESERVATION_ACTION_RELEASE;
    param->PR_OUT.Scope = scope;
    param->PR_OUT.Type = type;
    ppro = (PPRO_PARAMETER_LIST)param->PR_OUT.ParameterList;
    REVERSE_BYTES_QUAD(&(ppro->ReservationKey), &Key);

    if (!DeviceIoControl(DeviceHandle,
        IOCTL_STORAGE_PERSISTENT_RESERVE_OUT,
        param,
        param->Size,
        NULL,
        0,
        &bytesReturned,
        NULL))
    {
        return EnsureError(GetLastError());
    }
    return ERROR_SUCCESS;
}


DWORD
PRReserveCommand(
    HANDLE    DeviceHandle,
    ULONGLONG NewKey,
    DWORD     scope,
    DWORD     type)
{
    DWORD                           status = ERROR_SUCCESS;
    HELP_PERSISTENT_RESERVE_COMMAND Param = { 0 };
    PPERSISTENT_RESERVE_COMMAND     param = (PPERSISTENT_RESERVE_COMMAND)&Param;
    PPRO_PARAMETER_LIST             ppro;
    DWORD                           bytesReturned;

    RtlZeroMemory(&Param, sizeof(Param));

    param->Version = sizeof(PERSISTENT_RESERVE_COMMAND);
    param->Size = sizeof(Param);
    param->PR_OUT.ServiceAction = RESERVATION_ACTION_RESERVE;
    param->PR_OUT.Scope = (BYTE)scope;
    param->PR_OUT.Type = (BYTE)type;
    ppro = (PPRO_PARAMETER_LIST)param->PR_OUT.ParameterList;
    REVERSE_BYTES_QUAD(&(ppro->ReservationKey), &NewKey);

    if (!DeviceIoControl(DeviceHandle,
        IOCTL_STORAGE_PERSISTENT_RESERVE_OUT,
        param,
        param->Size,
        NULL,
        0,
        &bytesReturned,
        NULL))
    {
        return EnsureError(GetLastError());
    }

    return status;
}

DWORD
PRPreemptCommand(
    HANDLE    DeviceHandle,
    ULONGLONG NewKey,
    ULONGLONG OldKey,
    DWORD     scope,
    DWORD     type)
{
    DWORD                           status = ERROR_SUCCESS;
    HELP_PERSISTENT_RESERVE_COMMAND Param = { 0 };
    PPERSISTENT_RESERVE_COMMAND     param = (PPERSISTENT_RESERVE_COMMAND)&Param;
    PPRO_PARAMETER_LIST             ppro;
    DWORD                           bytesReturned;

    RtlZeroMemory(&Param, sizeof(Param));

    param->Version = sizeof(PERSISTENT_RESERVE_COMMAND);
    param->Size = sizeof(Param);
    param->PR_OUT.ServiceAction = RESERVATION_ACTION_PREEMPT;
    param->PR_OUT.Scope = (BYTE)scope;
    param->PR_OUT.Type = (BYTE)type;
    ppro = (PPRO_PARAMETER_LIST)param->PR_OUT.ParameterList;
    REVERSE_BYTES_QUAD(&(ppro->ReservationKey), &NewKey);
    REVERSE_BYTES_QUAD(&(ppro->ServiceActionReservationKey), &OldKey);

    if (!DeviceIoControl(DeviceHandle,
        IOCTL_STORAGE_PERSISTENT_RESERVE_OUT,
        param,
        param->Size,
        NULL,
        0,
        &bytesReturned,
        NULL))
    {
        return EnsureError(GetLastError());
    }

    return status;
}

DWORD
OfflineDisk(
    HANDLE DiskHandle,
    bool   offline,
    bool   readOnly)
{
    DWORD               status = ERROR_SUCCESS;
    SET_DISK_ATTRIBUTES offlineDisk;
    DWORD               bytesReturned;

    RtlZeroMemory(&offlineDisk, sizeof(offlineDisk));

    offlineDisk.Version = sizeof(offlineDisk);
    DWORD mask = 0;
    if (offline)
        mask |= DISK_ATTRIBUTE_OFFLINE;
    if (readOnly)
        mask |= DISK_ATTRIBUTE_READ_ONLY;
    offlineDisk.Attributes = mask;
    offlineDisk.AttributesMask = DISK_ATTRIBUTE_OFFLINE | DISK_ATTRIBUTE_READ_ONLY;

    if (!DeviceIoControl(DiskHandle,
        IOCTL_DISK_SET_DISK_ATTRIBUTES,
        &offlineDisk,
        sizeof(offlineDisk),
        NULL,
        0,
        &bytesReturned,
        NULL))
    {
        return EnsureError(GetLastError());
    }

    return status;
}
