//
//  Result+Conveniences.swift
//  AltStore
//
//  Created by Riley Testut on 5/22/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation

extension Result
{
    init(_ value: Success?, _ error: Failure?)
    {
        switch (value, error)
        {
        case (let value?, _): self = .success(value)
        case (_, let error?): self = .failure(error)
        case (nil, nil): preconditionFailure("Either value or error must be non-nil")
        }
    }
}

extension Result where Success == Void
{
    init(_ success: Bool, _ error: Failure?)
    {
        if success
        {
            self = .success(())
        }
        else if let error = error
        {
            self = .failure(error)
        }
        else
        {
            preconditionFailure("Error must be non-nil if success is false")
        }
    }
}
