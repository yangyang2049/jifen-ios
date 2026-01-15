//
//  UIViewControllerExtensions.swift
//  jifen
//
//  Helper extensions for UIViewController
//

import UIKit

extension UIViewController {
    func findTabBarController() -> UITabBarController? {
        if let tabBarController = self as? UITabBarController {
            return tabBarController
        }
        
        var parent = self.parent
        while parent != nil {
            if let tabBarController = parent as? UITabBarController {
                return tabBarController
            }
            parent = parent?.parent
        }
        
        return nil
    }
}

