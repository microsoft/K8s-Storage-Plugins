// iscsiHelper.cpp : Defines the entry point for the console application.
//

#include "stdafx.h"

#define NOMINMAX
#include <windows.h>
#define _NTSCSI_USER_MODE_
#include "scsi.h"
#include "iscsierr.h"
#include "Iscsidsc.h"

#include <iostream>
#include <optional>
#include <variant>
#include <vector>
#include <array>
#include <sstream>
#include <locale>
#include <codecvt>
#include <string>
#include <algorithm>
#include <limits>
#include "iscsiutil.h"

using namespace std;

#define PhysicalLocationBaseName L"\\\\.\\PhysicalDrive"


void PrintRegistrationKeys(HANDLE hDevice)
{
    auto keys = ReadKeys(hDevice);
    if (!keys.IsError())
    {
        wcout << "We have read the registration keys, and there are " << keys.GetValue().size() << "\n";

        for (const auto & key : keys.GetValue())
        {
            wcout << key << "\n";
        }
    }
    else
    {
        wcout << L"Error reading keys " << keys.GetError() << "\n";
    }
}

int PrintHelp()
{
    cout << "Print Help\n";
    cout << R"(#define RESERVATION_ACTION_READ_KEYS                    0x00
#define RESERVATION_ACTION_READ_RESERVATIONS            0x01

#define RESERVATION_ACTION_REGISTER                     0x00
#define RESERVATION_ACTION_RESERVE                      0x01
#define RESERVATION_ACTION_RELEASE                      0x02
#define RESERVATION_ACTION_CLEAR                        0x03
#define RESERVATION_ACTION_PREEMPT                      0x04
#define RESERVATION_ACTION_PREEMPT_ABORT                0x05
#define RESERVATION_ACTION_REGISTER_IGNORE_EXISTING     0x06

#define RESERVATION_SCOPE_LU                            0x00
#define RESERVATION_SCOPE_ELEMENT                       0x02

#define RESERVATION_TYPE_WRITE_EXCLUSIVE                0x01
#define RESERVATION_TYPE_EXCLUSIVE                      0x03
#define RESERVATION_TYPE_WRITE_EXCLUSIVE_REGISTRANTS    0x05
#define RESERVATION_TYPE_EXCLUSIVE_REGISTRANTS          0x06)";
    return 1;
}

int wmain(int argc, wchar_t * argv[])
{
    std::optional<DWORD>     diskNumber;
    std::optional<ULONGLONG> key;
    std::optional<ULONGLONG> serviceKey;
    std::optional<DWORD>     type;
    std::optional<DWORD>     scope;
    std::optional<DWORD>     offline;
    std::optional<DWORD>     readonly;
    bool                     dumpCommand = false;
    bool                     reserveCommand = false;
    bool                     preemptCommand = false;
    bool                     registerCommand = false;
    bool                     releaseCommand = false;
    bool                     clearCommand = false;
    bool                     setAttributesCommand = false;
    bool                     getReservations = false;
    bool                     getSessions = false;
    bool                     getRegistrations = false;
    std::array<pair<bool&, std::wstring>, 10> commands{
        pair<bool&, std::wstring> { dumpCommand, L"dump" }
    ,pair<bool&, std::wstring> { reserveCommand, L"reserve" }
    ,pair<bool&, std::wstring> { preemptCommand, L"preempt" }
    ,pair<bool&, std::wstring> { registerCommand, L"register" }
    ,pair<bool&, std::wstring> { releaseCommand, L"release" }
    ,pair<bool&, std::wstring> { clearCommand, L"clear" }
    ,pair<bool&, std::wstring> { setAttributesCommand, L"setAttributes" }
    ,pair<bool&, std::wstring> { getSessions, L"IscsiSessions" }
    ,pair<bool&, std::wstring> { getReservations, L"getReservations" }
    ,pair<bool&, std::wstring> { getRegistrations, L"getRegistrations" } };
    bool foundCommand = false;
    for (int i = 0; i < argc; ++i)
    {
        auto command = std::wstring(argv[i]);
        if (command == L"-disk")
        {
            if (i + 1 >= argc)
            {
                return PrintHelp();
            }
            diskNumber = std::stoul(std::wstring(argv[++i]));
            continue;
        }
        if (command == L"-key")
        {
            if (i + 1 >= argc)
            {
                return PrintHelp();
            }
            key = std::stoull(std::wstring(argv[++i]));
            continue;
        }
        if (command == L"-type")
        {
            if (i + 1 >= argc)
            {
                return PrintHelp();
            }
            type = std::stoul(std::wstring(argv[++i]));
            continue;
        }
        if (command == L"-scope")
        {
            if (i + 1 >= argc)
            {
                return PrintHelp();
            }
            scope = std::stoul(std::wstring(argv[++i]));
            continue;
        }
        if (command == L"-servicekey")
        {
            if (i + 1 >= argc)
            {
                return PrintHelp();
            }
            serviceKey = std::stoull(std::wstring(argv[++i]));
            continue;
        }
        if (command == L"-offline")
        {
            if (i + 1 >= argc)
            {
                return PrintHelp();
            }
            offline = std::stoul(std::wstring(argv[++i]));
            continue;
        }
        if (command == L"-readonly")
        {
            if (i + 1 >= argc)
            {
                return PrintHelp();
            }
            readonly = std::stoul(std::wstring(argv[++i]));
            continue;
        }
        for (auto & possibleCommand : commands)
        {
            if (command == possibleCommand.second)
            {
                possibleCommand.first = true;
                if (foundCommand)
                {
                    wcout << L"Extra parameter " << command << "\n";
                    return PrintHelp();
                }
                foundCommand = true;
            }
        }
    }
    if (getSessions)
    {
        ULONG                            sessionCount = 0;
        TypedBuffer<ISCSI_SESSION_INFOW> sessions(50);
        ULONG                            buffSize = (ULONG)(sessions.size());
        HRESULT                          hr;
        while ((hr = GetIScsiSessionListW(&buffSize, &sessionCount, sessions.GetPtr())) == ERROR_INSUFFICIENT_BUFFER)
        {
            sessions.resize(buffSize);
        }
        if (hr != ERROR_SUCCESS)
        {
            return hr;
        }
        wcout << L"Disk,Lun,TargetName";
        vector<ISCSI_DEVICE_ON_SESSIONW> devices(10);
        for (ULONG i = 0; i < sessionCount; ++i)
        {
            ISCSI_SESSION_INFOW & sessionInfo = sessions.GetPtr()[i];

            ULONG deviceCount = (ULONG)devices.size();
            while ((hr = GetDevicesForIScsiSessionW(&sessionInfo.SessionId, &deviceCount, devices.data())) == ERROR_INSUFFICIENT_BUFFER)
            {
                devices.resize(devices.size() * 2);
                deviceCount = (ULONG)devices.size();
            }
            if (hr == ERROR_SUCCESS)
            {
                for (ULONG j = 0; j < deviceCount; ++j)
                {
                    wcout << L"\n"
                        << devices[j].StorageDeviceNumber.DeviceNumber << L","
                        << ULONG(devices[j].ScsiAddress.Lun) << L","
                        << sessionInfo.TargetName;
                }
            }
            else
            {
                // we are just going to eat errors and have the caller determine if they couldn't find the lun
                //return hr;
            }
        }
        return 0;
    }
    if (!diskNumber.has_value())
    {
        cout << "No disk was specified \n";
        return PrintHelp();
    }

    std::wstring driveLocation;
    {
        std::wstringstream command;
        command << PhysicalLocationBaseName << diskNumber.value();
        driveLocation = command.str();
    }

    HANDLE hDevice = CreateFileW(driveLocation.c_str(),              // drive to open
        0,                                  // no access to the drive
        FILE_SHARE_READ | FILE_SHARE_WRITE, //
        NULL,                               // default security attributes
        OPEN_EXISTING,                      // disposition
        FILE_ATTRIBUTE_NORMAL,              // file attributes
        NULL);                             // do not copy file attributes

    if (hDevice == INVALID_HANDLE_VALUE) // cannot open the drive
    {
        DWORD err = ::GetLastError();
        cout << "Error opening drive with no access error " << err << "\n";
        return EnsureError(err);
    }

    HANDLE readHandle = CreateFileW(driveLocation.c_str(),              // drive to open
        GENERIC_READ,                       // read/write
        FILE_SHARE_READ | FILE_SHARE_WRITE, //
        NULL,                               // default security attributes
        OPEN_EXISTING,                      // disposition
        FILE_ATTRIBUTE_NORMAL,              // file attributes
        NULL);                             // do not copy file attributes

    if (readHandle == INVALID_HANDLE_VALUE) // cannot open the drive
    {
        DWORD err = ::GetLastError();
        cout << "Error opening drive with read access error " << err << "\n";
        return EnsureError(err);
    }

    HANDLE readWriteHandle = CreateFileW(driveLocation.c_str(),              // drive to open
        GENERIC_READ | GENERIC_WRITE,       // read/write
        FILE_SHARE_READ | FILE_SHARE_WRITE, //
        NULL,                               // default security attributes
        OPEN_EXISTING,                      // disposition
        FILE_ATTRIBUTE_NORMAL,              // file attributes
        NULL);                             // do not copy file attributes

    if (readWriteHandle == INVALID_HANDLE_VALUE) // cannot open the drive
    {
        DWORD err = ::GetLastError();
        cout << "Error opening drive with read access error " << err << "\n";
        return EnsureError(err);
    }

    if (dumpCommand)
    {
        wcout << L"Dumping registrations and reservations for disk " << driveLocation << L"\n\n";
        auto keys = ReadKeys(readHandle);
        auto reservations = ReadReservations(readHandle);

        if (keys.IsError())
        {
            cout << "Error reading registration keys : " << keys.GetError() << "\n";
            return keys.GetError();
        }
        cout << "Registration count : " << keys.GetValue().size() << "\n";

        for (const auto & regKey : keys.GetValue())
        {
            cout << regKey << "\n";
        }
        cout << "\n";

        if (reservations.IsError())
        {
            cout << "Error reading reservation keys : " << reservations.GetError() << "\n";
            return reservations.GetError();
        }
        cout << "Reservation count : " << reservations.GetValue().size() << "\n";
        if (reservations.GetValue().size() > 0)
        {
            cout << "key\ttype\tscope\taddress\n";
        }

        for (const auto & reservation : reservations.GetValue())
        {
            cout << reservation.key << "\t"
                << reservation.type << "\t"
                << reservation.scope << "\t"
                << reservation.address << "\n";
        }
        cout << "\n";
    }

    if (registerCommand)
    {
        if (!key.has_value())
        {
            cout << "missing parameter key\n";
            return PrintHelp();
        }
        DWORD error = PRRegisterKey(readWriteHandle, key.value());
        if (error != 0)
        {
            cout << "Registering key failed with error " << error << "\n";
            return error;
        }
    }
    if (preemptCommand)
    {
        if (!key.has_value())
        {
            cout << "missing parameter key\n";
            return PrintHelp();
        }
        if (!scope.has_value())
        {
            cout << "missing parameter scope\n";
            return PrintHelp();
        }
        if (!type.has_value())
        {
            cout << "missing parameter type\n";
            return PrintHelp();
        }
        if (!serviceKey.has_value())
        {
            cout << "missing parameter servicekey\n";
            return PrintHelp();
        }
        DWORD error = PRPreemptCommand(readWriteHandle,
            key.value(),
            serviceKey.value(),
            scope.value(),
            type.value());
        if (error != 0)
        {
            cout << "Reservation failed with error " << error << "\n";
            return error;
        }
    }
    if (reserveCommand)
    {
        if (!key.has_value())
        {
            cout << "missing parameter key\n";
            return PrintHelp();
        }
        if (!scope.has_value())
        {
            cout << "missing parameter scope\n";
            return PrintHelp();
        }
        if (!type.has_value())
        {
            cout << "missing parameter type\n";
            return PrintHelp();
        }
        DWORD error = PRReserveCommand(readWriteHandle,
            key.value(),
            scope.value(),
            type.value());
        if (error != 0)
        {
            cout << "Reservation failed with error " << error << "\n";
            return error;
        }
    }
    if (releaseCommand)
    {
        if (!key.has_value())
        {
            cout << "missing parameter key\n";
            return PrintHelp();
        }
        if (!scope.has_value())
        {
            cout << "missing parameter scope\n";
            return PrintHelp();
        }
        if (!type.has_value())
        {
            cout << "missing parameter type\n";
            return PrintHelp();
        }
        DWORD error = PRReleaseKey(readWriteHandle,
            key.value(),
            scope.value(),
            type.value());
        if (error != 0)
        {
            cout << "Release failed with error " << error << "\n";
            return error;
        }
    }
    if (setAttributesCommand)
    {
        if (!readonly.has_value())
        {
            cout << "missing parameter readonly\n";
            return PrintHelp();
        }
        if (!offline.has_value())
        {
            cout << "missing parameter offline\n";
            return PrintHelp();
        }
        DWORD error = OfflineDisk(readWriteHandle,
            offline.value() == 1,
            readonly.value() == 1);
        if (error != 0)
        {
            cout << "Offline disk failed with error " << error << "\n";
            return error;
        }
    }
    if (getReservations)
    {
        wcout << L"Reservations for disk " << driveLocation << L"";
        auto reservations = ReadReservations(readHandle);

        if (reservations.IsError())
        {
            cout << "\nError reading reservations keys : " << reservations.GetError() << "\n";
            return reservations.GetError();
        }

        wcout << L"\nKey,Type,Scope,Address";

        auto & reservs = reservations.GetValue();
        for (size_t i = 0; i < reservs.size(); ++i)
        {
            auto & reservation = reservs[i];
            cout << "\n"
                << reservation.key
                << "," << reservation.type
                << "," << reservation.scope
                << "," << reservation.address;
        }
    }
    if (getRegistrations)
    {
        wcout << L"Registrations for disk " << driveLocation << L"";
        auto keys = ReadKeys(readHandle);

        if (keys.IsError())
        {
            cout << "\nError reading registration keys : " << keys.GetError() << "\n";
            return keys.GetError();
        }

        for (const auto & regKey : keys.GetValue())
        {
            cout << "\n"
                << regKey;
        }
    }
    return 0;
}
